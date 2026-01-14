defmodule EthProofsClientWeb.HealthController do
  @moduledoc """
  Health check endpoints for monitoring and orchestration.
  """
  use EthProofsClientWeb, :controller

  alias EthProofsClient.{InputGenerator, Prover}

  @default_stuck_threshold_seconds 3600

  def index(conn, _params) do
    prover_status = safe_status(Prover)
    generator_status = safe_status(InputGenerator)

    health_status = %{
      status: overall_status(prover_status, generator_status),
      components: %{
        prover: component_health(prover_status, :prover),
        input_generator: component_health(generator_status, :generator)
      },
      timestamp: DateTime.utc_now()
    }

    status_code = if health_status.status == :healthy, do: 200, else: 503
    conn |> put_status(status_code) |> json(health_status)
  end

  def ready(conn, _params) do
    prover_status = safe_status(Prover)
    generator_status = safe_status(InputGenerator)

    if prover_status != nil and generator_status != nil do
      json(conn, %{ready: true})
    else
      conn |> put_status(503) |> json(%{ready: false})
    end
  end

  def live(conn, _params) do
    json(conn, %{live: true})
  end

  defp safe_status(module) do
    module.status()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp overall_status(nil, _), do: :unhealthy
  defp overall_status(_, nil), do: :unhealthy

  defp overall_status(prover_status, _generator_status) do
    if prover_stuck?(prover_status) do
      :unhealthy
    else
      :healthy
    end
  end

  defp component_health(nil, _type), do: %{status: :down}

  defp component_health(status, :prover) do
    base = %{
      status: sanitize_status(status.status),
      queue_length: Map.get(status, :queue_length, 0)
    }

    if prover_stuck?(status) do
      Map.merge(base, %{
        warning: :potentially_stuck,
        proving_duration_seconds: Map.get(status, :proving_duration_seconds)
      })
    else
      base
    end
  end

  defp component_health(status, :generator) do
    %{
      status: sanitize_status(status.status),
      queue_length: Map.get(status, :queue_length, 0),
      processed_count: Map.get(status, :processed_count, 0)
    }
  end

  defp prover_stuck?(%{proving_duration_seconds: seconds}) when is_integer(seconds) do
    seconds > stuck_threshold()
  end

  defp prover_stuck?(_), do: false

  defp stuck_threshold do
    case System.get_env("PROVER_STUCK_THRESHOLD_SECONDS") do
      nil -> @default_stuck_threshold_seconds
      val -> String.to_integer(val)
    end
  end

  defp sanitize_status(:idle), do: :idle
  defp sanitize_status({:proving, block_number}), do: {:proving, block_number}
  defp sanitize_status({:generating, block_number}), do: {:generating, block_number}
  defp sanitize_status({:generating, block_number, _ref}), do: {:generating, block_number}
  defp sanitize_status(other), do: other
end
