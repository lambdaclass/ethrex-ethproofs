defmodule EthProofsClient.Prover do
  use GenServer
  require Logger

  @output_dir "output"
  @default_zisk_action "prove"

  def start_link(elf_path, _opts \\ []) do
    GenServer.start_link(__MODULE__, %{elf: elf_path}, name: __MODULE__)
  end

  def prove(block_number, input_path) do
    GenServer.cast(__MODULE__, {:prove, block_number, input_path})
  end

  @impl true
  def init(%{elf: elf}) do
    # By setting Process.flag(:trap_exit, true) in the init function and
    # linking the port with Process.link(port) after opening it, the
    # GenServer will now properly handle port exits without crashing. When
    # cargo-zisk dies due to an OOM (or any other reason), the GenServer
    # receives an {:EXIT, port, reason} message and continues processing
    # the queue, preventing the application from terminating.
    Process.flag(:trap_exit, true)
    zisk_action = resolve_zisk_action()

    # :execute is for fast local debugging; it runs without generating or reporting proofs.
    if zisk_action != :prove do
      Logger.info(
        "ZisK action set to #{zisk_action_label(zisk_action)}; proof reporting is disabled."
      )
    end

    {:ok,
     %{
       queue: :queue.new(),
       proving: false,
       elf: elf,
       port: nil,
       current_block: nil,
       zisk_action: zisk_action,
       proving_notification_sent: false
     }}
  end

  @impl true
  def handle_cast({:prove, block_number, input_path}, state) do
    new_queue = :queue.in({block_number, input_path}, state.queue)

    if state.zisk_action == :prove do
      case EthProofsClient.Rpc.queued_proof(block_number) do
        {:ok, _proof_id} ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to queue proof for block #{block_number}: #{reason}")
      end
    end

    if state.proving do
      Logger.info(
        "Proving already in progress, enqueued input path #{input_path} for block #{block_number}"
      )

      {:noreply, %{state | queue: new_queue}}
    else
      send(self(), :prove_next)
      {:noreply, %{state | queue: new_queue, proving: true}}
    end
  end

  @impl true
  def handle_info(:prove_next, %{queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, {block_number, input_path}}, new_queue} ->
        output_dir_path = Path.join(@output_dir, Integer.to_string(block_number))
        zisk_action_label = zisk_action_label(state.zisk_action)

        # Create output directory if it doesn't exist
        File.mkdir_p!(output_dir_path)

        port =
          Port.open(
            {:spawn_executable, System.find_executable("cargo-zisk")},
            [
              :binary,
              :exit_status,
              args: zisk_args(state.zisk_action, state.elf, input_path, output_dir_path)
            ]
          )

        # By setting Process.flag(:trap_exit, true) in the init function and
        # linking the port with Process.link(port) after opening it, the
        # GenServer will now properly handle port exits without crashing. When
        # cargo-zisk dies due to an OOM (or any other reason), the GenServer
        # receives an {:EXIT, port, reason} message and continues processing
        # the queue, preventing the application from terminating.
        Process.link(port)

        if state.zisk_action == :prove do
          case EthProofsClient.Rpc.proving_proof(block_number) do
            {:ok, _proof_id} ->
              :ok

            {:error, reason} ->
              Logger.error("Failed to mark proving for block #{block_number}: #{reason}")
          end
        end

        Logger.info(
          "Started cargo-zisk #{zisk_action_label} for ELF: #{state.elf}, INPUT: #{input_path}, BLOCK: #{block_number}, PORT: #{inspect(port)}"
        )

        {:noreply,
         %{
           state
           | queue: new_queue,
             proving: true,
             port: port,
             current_block: block_number,
             proving_notification_sent: false
         }}

      {:empty, _queue} ->
        # Queue is empty, stop proving
        {:noreply, %{state | proving: false}}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, state) do
    case Map.fetch(state, :port) do
      {:ok, ^port} ->
        Logger.debug("cargo-zisk output: #{data}")

        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, state) do
    case Map.fetch(state, :port) do
      {:ok, ^port} ->
        zisk_action_label = zisk_action_label(state.zisk_action)
        Logger.info("cargo-zisk #{zisk_action_label} exited with status: #{status}")

        if state.zisk_action == :prove do
          state =
            cond do
              status != 0 ->
                Logger.error(
                  "Proof failed for block #{state.current_block} with cargo-zisk #{zisk_action_label} (status #{status})"
                )

                maybe_notify_proving_result(state, :error)

              true ->
                case read_proof_data(state.current_block) do
                  {:ok,
                   %{cycles: proving_cycles, time: proving_time, proof: proof, id: verifier_id}} ->
                    Logger.info(
                      "Proved block #{state.current_block} in #{proving_time / 1000} seconds using #{proving_cycles} cycles"
                    )

                    case EthProofsClient.Rpc.proved_proof(
                           state.current_block,
                           proving_time,
                           proving_cycles,
                           proof,
                           verifier_id
                         ) do
                      {:ok, _proof_id} ->
                        maybe_notify_proving_result(state, :ok)

                      {:error, reason} ->
                        Logger.error(
                          "Failed to submit proved proof for block #{state.current_block}: #{reason}"
                        )

                        maybe_notify_proving_result(state, :error)
                    end

                  {:error, reason} ->
                    Logger.error(
                      "Failed to read proof data for block #{state.current_block}: #{reason}. Call to EthProofsClient.Rpc.proved_proof skipped."
                    )

                    maybe_notify_proving_result(state, :error)
                end
            end

          # Process finished, trigger next item
          send(self(), :prove_next)

          {:noreply, %{state | port: nil, current_block: nil}}
        else
          execution_result =
            if status == 0 do
              Logger.info(
                "Executed block #{state.current_block} with cargo-zisk #{zisk_action_label}"
              )

              :ok
            else
              Logger.error(
                "Execution failed for block #{state.current_block} with cargo-zisk #{zisk_action_label} (status #{status})"
              )

              :error
            end

          EthProofsClient.Notifications.block_execution_result(
            state.current_block,
            execution_result
          )

          send(self(), :prove_next)

          {:noreply, %{state | port: nil, current_block: nil}}
        end

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:EXIT, port, _reason}, state) do
    if state.port == port and not is_nil(state.current_block) do
      Logger.warning("Port died, processing next input")

      state = maybe_notify_proving_result(state, :error)

      send(self(), :prove_next)

      {:noreply, %{state | port: nil, current_block: nil}}
    else
      {:noreply, state}
    end
  end

  defp read_proof_data(block_number) do
    block_dir = Integer.to_string(block_number)

    result_path = Path.join([@output_dir, block_dir, "result.json"])

    proof_paths = [
      Path.join([@output_dir, block_dir, "vadcop_final_proof.compressed.bin"]),
      Path.join([@output_dir, block_dir, "vadcop_final_proof.bin"])
    ]

    with {:ok, result_content} <- File.read(result_path),
         {:ok, %{"cycles" => cycles, "time" => time, "id" => id}} <- Jason.decode(result_content),
         {:ok, proof_binary} <- read_first_file(proof_paths) do
      {:ok,
       %{
         cycles: cycles,
         time: trunc(time * 1000),
         proof: Base.encode64(proof_binary, padding: false) |> String.replace(~r/\s+/, ""),
         id: id
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_first_file(paths) do
    Enum.reduce_while(paths, {:error, :enoent}, fn path, _acc ->
      case File.read(path) do
        {:ok, contents} -> {:halt, {:ok, contents}}
        {:error, _reason} -> {:cont, {:error, :enoent}}
      end
    end)
  end

  defp resolve_zisk_action do
    action =
      Application.get_env(:ethproofs_client, :zisk_action, @default_zisk_action)
      |> to_string()
      |> String.downcase()

    case action do
      "prove" ->
        :prove

      "execute" ->
        :execute

      other ->
        Logger.warning("Unknown ZISK_ACTION=#{inspect(other)}, defaulting to prove.")
        :prove
    end
  end

  defp zisk_action_label(:prove), do: "prove"
  defp zisk_action_label(:execute), do: "execute"

  defp zisk_args(:prove, elf_path, input_path, output_dir_path) do
    ["prove", "-e", elf_path, "-i", input_path, "-o", output_dir_path, "-a", "-u"]
  end

  defp zisk_args(:execute, elf_path, input_path, _output_dir_path) do
    ["execute", "-e", elf_path, "-i", input_path, "-u"]
  end

  defp maybe_notify_proving_result(state, result) when result in [:ok, :error] do
    if state.zisk_action == :prove and is_integer(state.current_block) and
         not state.proving_notification_sent do
      EthProofsClient.Notifications.block_proving_result(state.current_block, result)
      %{state | proving_notification_sent: true}
    else
      state
    end
  end
end
