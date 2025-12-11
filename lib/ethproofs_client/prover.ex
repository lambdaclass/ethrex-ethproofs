defmodule EthProofsClient.Prover do
  use GenServer
  require Logger

  def start_link(elf_path, _opts \\ []) do
    GenServer.start_link(__MODULE__, %{elf: elf_path}, name: __MODULE__)
  end

  def prove(input_path) do
    GenServer.cast(__MODULE__, {:prove, input_path})
  end

  @impl true
  def init(%{elf: elf}) do
    {:ok, %{queue: :queue.new(), proving: false, elf: elf, port: nil}}
  end

  @impl true
  def handle_cast({:prove, input_path}, state) do
    new_queue = :queue.in(input_path, state.queue)

    if state.proving do
      Logger.info("Proving already in progress, enqueued input path #{input_path}")
      {:noreply, %{state | queue: new_queue}}
    else
      send(self(), :prove_next)
      {:noreply, %{state | queue: new_queue, proving: true}}
    end
  end

  @impl true
  def handle_info(:prove_next, %{queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, input_path}, new_queue} ->
        # Dequeued an item, start proving
        port =
          Port.open(
            {:spawn_executable, System.find_executable("cargo-zisk")},
            [
              :binary,
              :exit_status,
              args: ["execute", "-e", state.elf, "-i", input_path, "-u"]
              # args: ["prove", "-e", state.elf, "-i", input_path, "-a", "-u"]
            ]
          )

        Logger.info(
          "Started cargo-zisk prover for ELF: #{state.elf}, INPUT: #{input_path}, PORT: #{inspect(port)}"
        )

        {:noreply, %{state | queue: new_queue, proving: true, port: port}}

      {:empty, _queue} ->
        # Queue is empty, stop proving
        {:noreply, %{state | proving: false}}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, state) do
    case Map.fetch(state, :port) do
      {:ok, ^port} ->
        Logger.info("cargo-zisk output: #{data}")
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

        # Process finished, trigger next item
        send(self(), :prove_next)

        {:noreply, %{state | port: nil}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:EXIT, _port, _reason}, state) do
    Logger.warning("Port died, proving next input")
    send(self(), :prove_next)

    {:noreply, %{state | port: nil}}
  end
end
