defmodule EthProofsClient.HealthRouter do
  @moduledoc """
  HTTP router exposing health and status endpoints.

  ## Endpoints

  - `GET /health` - Returns health status of all components
  - `GET /health/ready` - Returns 200 if the application is ready to accept work
  - `GET /health/live` - Returns 200 if the application is alive (for liveness probes)

  ## Configuration

  Set the `HEALTH_PORT` environment variable to change the port (default: 4000).
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  # GET /health - Returns comprehensive health information about the application
  get "/health" do
    health_data = collect_health_data()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(health_status_code(health_data), Jason.encode!(health_data))
  end

  # GET /health/ready - Readiness probe, returns 200 if ready to process blocks
  get "/health/ready" do
    if ready?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ready"}))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(503, Jason.encode!(%{status: "not_ready"}))
    end
  end

  # GET /health/live - Liveness probe, returns 200 if the application is alive
  get "/health/live" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "alive"}))
  end

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "not_found"}))
  end

  # --- Private Functions ---

  defp collect_health_data do
    %{
      status: overall_status(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      uptime_seconds: uptime_seconds(),
      components: %{
        prover: prover_health(),
        input_generator: input_generator_health(),
        task_supervisor: task_supervisor_health()
      },
      system: system_health()
    }
  end

  # Default: 1 hour, configurable via PROVER_STUCK_THRESHOLD_SECONDS
  @default_prover_stuck_threshold_seconds 60 * 60

  defp prover_health do
    case safe_call(EthProofsClient.Prover, :status) do
      {:ok, status} ->
        proving_duration = status.proving_duration_seconds
        threshold = prover_stuck_threshold()

        health_status =
          cond do
            proving_duration != nil and proving_duration > threshold ->
              "stuck"

            true ->
              "up"
          end

        %{
          status: health_status,
          state: format_state(status.status),
          queue_length: status.queue_length,
          queued_blocks: status.queued_blocks,
          proving_since: format_datetime(status.proving_since),
          proving_duration_seconds: proving_duration
        }

      {:error, reason} ->
        %{status: "down", error: inspect(reason)}
    end
  end

  defp input_generator_health do
    case safe_call(EthProofsClient.InputGenerator, :status) do
      {:ok, status} ->
        %{
          status: "up",
          state: format_state(status.status),
          queue_length: status.queue_length,
          queued_blocks: status.queued_blocks,
          processed_count: status.processed_count
        }

      {:error, reason} ->
        %{status: "down", error: inspect(reason)}
    end
  end

  defp task_supervisor_health do
    case Process.whereis(EthProofsClient.TaskSupervisor) do
      nil ->
        %{status: "down"}

      pid ->
        children = Task.Supervisor.children(EthProofsClient.TaskSupervisor)

        %{
          status: "up",
          pid: inspect(pid),
          active_tasks: length(children)
        }
    end
  end

  defp system_health do
    memory = :erlang.memory()

    %{
      beam_memory_mb: Float.round(memory[:total] / 1_048_576, 2),
      process_count: :erlang.system_info(:process_count),
      scheduler_count: :erlang.system_info(:schedulers_online),
      otp_release: :erlang.system_info(:otp_release) |> List.to_string()
    }
  end

  defp overall_status do
    prover = prover_health()
    generator = input_generator_health()
    supervisor_up? = Process.whereis(EthProofsClient.TaskSupervisor) != nil

    cond do
      prover.status == "down" or generator.status == "down" or not supervisor_up? ->
        "unhealthy"

      prover.status == "stuck" ->
        "degraded"

      true ->
        "healthy"
    end
  end

  defp ready? do
    # Ready if healthy (not degraded or unhealthy)
    overall_status() == "healthy"
  end

  defp health_status_code(%{status: "healthy"}), do: 200
  defp health_status_code(_), do: 503

  defp uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end

  defp safe_call(module, function) do
    {:ok, GenServer.call(module, function, 5000)}
  catch
    :exit, reason -> {:error, reason}
  end

  defp format_state(:idle), do: "idle"
  defp format_state({:proving, block_number}), do: "proving_#{block_number}"
  defp format_state({:generating, block_number}), do: "generating_#{block_number}"
  defp format_state(other), do: inspect(other)

  defp format_datetime(nil), do: nil
  defp format_datetime(datetime), do: DateTime.to_iso8601(datetime)

  defp prover_stuck_threshold do
    case System.get_env("PROVER_STUCK_THRESHOLD_SECONDS") do
      nil -> @default_prover_stuck_threshold_seconds
      value -> String.to_integer(value)
    end
  end
end
