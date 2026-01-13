defmodule EthProofsClientWeb.DashboardLive do
  @moduledoc """
  LiveView dashboard displaying real-time status of the EthProofs Client.
  Updates every second by polling the GenServers directly.
  """

  use EthProofsClientWeb, :live_view
  require Logger

  alias EthProofsClient.{InputGenerator, Prover, ProvedBlocksStore}

  @tick_interval 1_000

  @impl true
  def mount(_params, _session, socket) do
    Logger.info("DashboardLive mount - connected?: #{connected?(socket)}")

    socket = assign(socket, page_title: "Dashboard", tick: 0)

    # Only start the timer when the WebSocket is connected
    if connected?(socket) do
      Logger.info("DashboardLive: WebSocket connected, starting timer")
      # Schedule first tick
      Process.send_after(self(), :tick, 0)
    else
      Logger.info("DashboardLive: Initial render (no WebSocket yet)")
    end

    {:ok, fetch_all_data(socket)}
  end

  @impl true
  def handle_info(:tick, socket) do
    new_tick = socket.assigns.tick + 1
    Logger.info("DashboardLive tick ##{new_tick}")

    # Schedule next tick
    Process.send_after(self(), :tick, @tick_interval)

    # Increment tick counter to force re-render and fetch fresh data
    socket =
      socket
      |> assign(:tick, new_tick)
      |> fetch_all_data()

    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Fetch all data from GenServers
  defp fetch_all_data(socket) do
    prover_status = safe_call(Prover, :status)
    generator_status = safe_call(InputGenerator, :status)
    proved_blocks = safe_call(ProvedBlocksStore, :list_blocks) || []

    # Extract next_block_info from generator_status and recalculate countdown
    next_block_info =
      case generator_status do
        %{last_block_info: info} when not is_nil(info) ->
          # Recalculate estimated_seconds based on current time
          recalculate_countdown(info)

        _ ->
          nil
      end

    socket
    |> assign(:prover_status, prover_status)
    |> assign(:generator_status, generator_status)
    |> assign(:proved_blocks, proved_blocks)
    |> assign(:next_block_info, next_block_info)
  end

  # Recalculate the countdown based on current time
  defp recalculate_countdown(%{block_timestamp: timestamp, blocks_remaining: remaining} = info) do
    elapsed = System.system_time(:second) - timestamp
    estimated_seconds = max(0, remaining * 12 - elapsed)
    Map.put(info, :estimated_seconds, estimated_seconds)
  end

  defp recalculate_countdown(info), do: info

  defp safe_call(module, function, args \\ []) do
    apply(module, function, args)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Header with current block info --%>
      <section class="text-center py-8">
        <h2 class="text-3xl font-bold text-white mb-2">Proof Generation Status</h2>
        <p class="text-slate-400 mb-6">
          Real-time monitoring of Ethereum block proof generation
          <span class="text-slate-600 text-xs ml-2">(update #<%= @tick %>)</span>
        </p>

        <%= if @next_block_info do %>
          <div class="inline-flex items-center gap-8 bg-slate-800/60 border border-slate-700/50 rounded-xl px-8 py-4">
            <div class="text-left">
              <div class="text-sm text-slate-400">Current Block</div>
              <div class="text-2xl font-bold text-white font-mono">
                <%= @next_block_info.current_block %>
              </div>
            </div>
            <div class="w-px h-12 bg-slate-700"></div>
            <div class="text-left">
              <div class="text-sm text-slate-400">Next Target Block</div>
              <div class="text-2xl font-bold text-cyan-400 font-mono">
                <%= @next_block_info.next_target_block %>
              </div>
            </div>
            <div class="w-px h-12 bg-slate-700"></div>
            <div class="text-left">
              <div class="text-sm text-slate-400">Estimated Time</div>
              <div class="text-2xl font-bold text-white font-mono tabular-nums">
                <%= format_countdown(@next_block_info.estimated_seconds) %>
              </div>
            </div>
          </div>
        <% else %>
          <div class="inline-flex items-center gap-4 bg-slate-800/60 border border-slate-700/50 rounded-xl px-8 py-4">
            <div class="animate-spin h-5 w-5 border-2 border-cyan-400 border-t-transparent rounded-full"></div>
            <span class="text-slate-400">Connecting to Ethereum node...</span>
          </div>
        <% end %>
      </section>

      <%!-- Metrics Row --%>
      <section class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <.metric_card label="Blocks Proved" value={length(@proved_blocks)}>
          <:icon>
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </:icon>
        </.metric_card>

        <.metric_card label="Generator Queue" value={get_queue_length(@generator_status)}>
          <:icon>
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
            </svg>
          </:icon>
        </.metric_card>

        <.metric_card label="Prover Queue" value={get_prover_queue_length(@prover_status)}>
          <:icon>
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
            </svg>
          </:icon>
        </.metric_card>

        <.metric_card label="Proving Time" value={format_proving_time(@prover_status)}>
          <:icon>
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </:icon>
        </.metric_card>
      </section>

      <%!-- Component Status Cards --%>
      <section class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <.component_card
          name="Input Generator"
          status={get_generator_status_atom(@generator_status)}
          details={generator_details(@generator_status)}
        />
        <.component_card
          name="Prover"
          status={get_prover_status_atom(@prover_status)}
          details={prover_details(@prover_status)}
        />
      </section>

      <%!-- Proved Blocks Table --%>
      <section class="bg-slate-800/40 border border-slate-700/50 rounded-xl overflow-hidden">
        <div class="px-6 py-4 border-b border-slate-700/50">
          <h3 class="text-lg font-semibold text-white">Recently Proved Blocks</h3>
        </div>
        <.blocks_table id="proved-blocks" rows={@proved_blocks}>
          <:col :let={block} label="Block" class="text-white">
            <.etherscan_link block_number={block.block_number} />
          </:col>
          <:col :let={block} label="Proved At" class="text-slate-300">
            {format_datetime(block.proved_at)}
          </:col>
          <:col :let={block} label="Proving Duration" class="text-slate-300">
            {format_duration_long(block.proving_duration_seconds)}
          </:col>
          <:col :let={block} label="Input Gen Duration" class="text-slate-300">
            {format_duration_long(block.input_generation_duration_seconds)}
          </:col>
        </.blocks_table>
      </section>
    </div>
    """
  end

  # Helper functions

  defp get_queue_length(nil), do: 0
  defp get_queue_length(%{queue_length: len}), do: len
  defp get_queue_length(_), do: 0

  defp get_prover_queue_length(nil), do: 0
  defp get_prover_queue_length(%{queue_length: len}), do: len
  defp get_prover_queue_length(_), do: 0

  defp get_generator_status_atom(nil), do: :idle
  defp get_generator_status_atom(%{status: :idle}), do: :idle
  defp get_generator_status_atom(%{status: {:generating, _}}), do: :generating
  defp get_generator_status_atom(_), do: :idle

  defp get_prover_status_atom(nil), do: :idle
  defp get_prover_status_atom(%{status: :idle}), do: :idle
  defp get_prover_status_atom(%{status: {:proving, _}}), do: :proving
  defp get_prover_status_atom(_), do: :idle

  defp generator_details(nil), do: %{}

  defp generator_details(%{status: {:generating, block_number}} = status) do
    %{
      "Current Block" => block_number,
      "Queue Length" => Map.get(status, :queue_length, 0),
      "Processed" => Map.get(status, :processed_count, 0)
    }
  end

  defp generator_details(status) do
    %{
      "Queue Length" => Map.get(status, :queue_length, 0),
      "Processed" => Map.get(status, :processed_count, 0)
    }
  end

  defp prover_details(nil), do: %{}

  defp prover_details(%{status: {:proving, block_number}} = status) do
    %{
      "Current Block" => block_number,
      "Queue Length" => Map.get(status, :queue_length, 0),
      "Duration" => format_duration_long(Map.get(status, :proving_duration_seconds))
    }
  end

  defp prover_details(status) do
    %{
      "Queue Length" => Map.get(status, :queue_length, 0)
    }
  end

  defp format_proving_time(nil), do: "-"
  defp format_proving_time(%{proving_duration_seconds: nil}), do: "-"
  defp format_proving_time(%{proving_duration_seconds: secs}), do: format_duration_long(secs)
  defp format_proving_time(_), do: "-"

  defp format_datetime(nil), do: "-"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_datetime(_), do: "-"

  defp format_duration_long(nil), do: "-"

  defp format_duration_long(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end

  defp format_duration_long(_), do: "-"

  defp format_countdown(seconds) when is_integer(seconds) and seconds >= 0 do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_countdown(_), do: "--:--"
end
