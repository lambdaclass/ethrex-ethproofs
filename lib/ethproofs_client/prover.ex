defmodule EthProofsClient.Prover do
  use GenServer
  require Logger

  @output_dir "output"

  def start_link(elf_path, _opts \\ []) do
    GenServer.start_link(__MODULE__, %{elf: elf_path}, name: __MODULE__)
  end

  def prove(block_number, input_path) do
    GenServer.cast(__MODULE__, {:prove, block_number, input_path})
  end

  @impl true
  def init(%{elf: elf}) do
    {:ok, %{queue: :queue.new(), proving: false, elf: elf, port: nil, current_block: nil}}
  end

  @impl true
  def handle_cast({:prove, block_number, input_path}, state) do
    new_queue = :queue.in({block_number, input_path}, state.queue)

    {:ok, _proof_id} = EthProofsClient.Rpc.queued_proof(block_number)

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

        # Create output directory if it doesn't exist
        File.mkdir_p!(output_dir_path)

        port =
          Port.open(
            {:spawn_executable, System.find_executable("cargo-zisk")},
            [
              :binary,
              :exit_status,
              args: [
                "prove",
                "-e",
                state.elf,
                "-i",
                input_path,
                "-o",
                output_dir_path,
                "-a",
                "-u"
              ]
            ]
          )

        {:ok, _proof_id} =
          EthProofsClient.Rpc.proving_proof(block_number)

        Logger.info(
          "Started cargo-zisk prover for ELF: #{state.elf}, INPUT: #{input_path}, BLOCK: #{block_number}, PORT: #{inspect(port)}"
        )

        {:noreply,
         %{state | queue: new_queue, proving: true, port: port, current_block: block_number}}

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
        Logger.info("cargo-zisk exited with status: #{status}")

        case read_proof_data(state.current_block) do
          {:ok, %{cycles: proving_cycles, time: proving_time, proof: proof}} ->
            Logger.info(
              "Proved block #{state.current_block} in #{proving_time} seconds using #{proving_cycles} cycles"
            )

            {:ok, _proof_id} =
              EthProofsClient.Rpc.proved_proof(
                state.current_block,
                proving_time,
                proving_cycles,
                proof
              )

            # Process finished, trigger next item
            send(self(), :prove_next)

          {:error, reason} ->
            Logger.error(
              "Failed to read proof data for block #{state.current_block}: #{reason}. Call to EthProofsClient.Rpc.proved_proof skipped."
            )

            # Still trigger next to avoid blocking the queue
            send(self(), :prove_next)
        end

        {:noreply, %{state | port: nil, current_block: nil}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:EXIT, _port, _reason}, state) do
    Logger.warning("Port died, proving next input")

    send(self(), :prove_next)

    {:noreply, %{state | port: nil, current_block: nil}}
  end

  defp read_proof_data(block_number) do
    block_dir = Integer.to_string(block_number)

    result_path = Path.join([@output_dir, block_dir, "result.json"])

    proof_path = Path.join([@output_dir, block_dir, "vadcop_final_proof.compressed.bin"])

    with {:ok, result_content} <- File.read(result_path),
         {:ok, %{"cycles" => cycles, "time" => time, "id" => _id}} <- Jason.decode(result_content),
         {:ok, proof_binary} <- File.read(proof_path) do
      {:ok, %{cycles: cycles, time: time, proof: Base.encode64(proof_binary)}}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
