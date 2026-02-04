defmodule EthProofsClientWeb.CoreComponents do
  @moduledoc """
  Provides core UI components styled with DaisyUI-inspired dark theme.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders a status badge with appropriate styling based on status.
  """
  attr(:status, :atom, required: true)
  attr(:class, :string, default: nil)

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium",
      status_badge_class(@status),
      @class
    ]}>
      <span class={["w-2 h-2 rounded-full", status_dot_class(@status)]}></span>
      {status_text(@status)}
    </span>
    """
  end

  defp status_badge_class(:idle), do: "bg-slate-700/50 text-slate-300"
  defp status_badge_class(:generating), do: "bg-cyan-900/50 text-cyan-300"
  defp status_badge_class(:proving), do: "bg-amber-900/50 text-amber-300"
  defp status_badge_class(:completed), do: "bg-emerald-900/50 text-emerald-300"
  defp status_badge_class(:failed), do: "bg-red-900/50 text-red-300"
  defp status_badge_class(_), do: "bg-slate-700/50 text-slate-300"

  defp status_dot_class(:idle), do: "bg-slate-400"
  defp status_dot_class(:generating), do: "bg-cyan-400 animate-pulse"
  defp status_dot_class(:proving), do: "bg-amber-400 animate-pulse"
  defp status_dot_class(:completed), do: "bg-emerald-400"
  defp status_dot_class(:failed), do: "bg-red-400"
  defp status_dot_class(_), do: "bg-slate-400"

  defp status_text(:idle), do: "Idle"
  defp status_text(:generating), do: "Generating"
  defp status_text(:proving), do: "Proving"
  defp status_text(:completed), do: "Completed"
  defp status_text(:failed), do: "Failed"
  defp status_text(status), do: to_string(status)

  @doc """
  Renders a stage badge indicating which pipeline stage failed.
  """
  attr(:stage, :atom, required: true)
  attr(:class, :string, default: nil)

  def stage_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium",
      stage_badge_class(@stage),
      @class
    ]}>
      {stage_text(@stage)}
    </span>
    """
  end

  defp stage_badge_class(:input_generation), do: "bg-cyan-900/50 text-cyan-300"
  defp stage_badge_class(:proving), do: "bg-amber-900/50 text-amber-300"
  defp stage_badge_class(_), do: "bg-slate-700/50 text-slate-300"

  defp stage_text(:input_generation), do: "Input Generation"
  defp stage_text(:proving), do: "Proving"
  defp stage_text(stage), do: to_string(stage)

  @doc """
  Renders a block status badge indicating whether a block was proved or failed.
  """
  attr(:status, :atom, required: true)
  attr(:stage, :atom, default: nil)
  attr(:class, :string, default: nil)

  def block_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium",
      block_status_badge_class(@status),
      @class
    ]}>
      <span class={["w-2 h-2 rounded-full", block_status_dot_class(@status)]}></span>
      {block_status_text(@status, @stage)}
    </span>
    """
  end

  defp block_status_badge_class(:proved), do: "bg-emerald-900/50 text-emerald-300"
  defp block_status_badge_class(:failed), do: "bg-red-900/50 text-red-300"
  defp block_status_badge_class(_), do: "bg-slate-700/50 text-slate-300"

  defp block_status_dot_class(:proved), do: "bg-emerald-400"
  defp block_status_dot_class(:failed), do: "bg-red-400"
  defp block_status_dot_class(_), do: "bg-slate-400"

  defp block_status_text(:proved, _stage), do: "Proved"
  defp block_status_text(:failed, :input_generation), do: "Failed: Input Gen"
  defp block_status_text(:failed, :proving), do: "Failed: Proving"
  defp block_status_text(:failed, _stage), do: "Failed"
  defp block_status_text(status, _stage), do: to_string(status)

  @doc """
  Renders a metric card with a label and value.
  """
  attr(:label, :string, required: true)
  attr(:value, :any, required: true)
  attr(:class, :string, default: nil)
  slot(:icon)

  def metric_card(assigns) do
    ~H"""
    <div class={[
      "bg-slate-800/60 border border-slate-700/50 rounded-xl p-5",
      "hover:bg-slate-800/80 hover:border-cyan-500/30 transition-all duration-200",
      @class
    ]}>
      <div class="flex items-center gap-3 mb-2">
        <div :if={@icon != []} class="text-cyan-400">
          {render_slot(@icon)}
        </div>
        <span class="text-sm text-slate-400 font-medium">{@label}</span>
      </div>
      <div class="text-2xl font-bold text-white">{@value}</div>
    </div>
    """
  end

  @doc """
  Renders a component status card showing the state of a GenServer.
  """
  attr(:name, :string, required: true)
  attr(:status, :atom, required: true)
  attr(:details, :map, default: %{})
  attr(:class, :string, default: nil)

  def component_card(assigns) do
    ~H"""
    <div class={[
      "bg-slate-800/60 border border-slate-700/50 rounded-xl p-5",
      component_border_class(@status),
      "transition-all duration-200",
      @class
    ]}>
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-white">{@name}</h3>
        <.status_badge status={@status} />
      </div>
      <div class="space-y-2">
        <div :for={{key, value} <- @details} class="flex justify-between text-sm">
          <span class="text-slate-400">{format_key(key)}</span>
          <span class="text-slate-200 font-medium">{format_value(value)}</span>
        </div>
      </div>
    </div>
    """
  end

  defp component_border_class(:idle), do: "hover:border-slate-600"
  defp component_border_class(:generating), do: "border-cyan-500/30 shadow-cyan-500/10 shadow-lg"
  defp component_border_class(:proving), do: "border-amber-500/30 shadow-amber-500/10 shadow-lg"
  defp component_border_class(:completed), do: "hover:border-emerald-500/30"
  defp component_border_class(:failed), do: "border-red-500/30"
  defp component_border_class(_), do: "hover:border-slate-600"

  defp format_key(key) when is_atom(key),
    do: key |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp format_key(key), do: key

  defp format_value(nil), do: "-"
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp format_value(value), do: to_string(value)

  @doc """
  Renders a table for proved blocks.
  """
  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:class, :string, default: nil)

  slot :col, required: true do
    attr(:label, :string, required: true)
    attr(:class, :string)
  end

  def blocks_table(assigns) do
    ~H"""
    <div class={["overflow-x-auto", @class]}>
      <table class="w-full">
        <thead>
          <tr class="border-b border-slate-700/50">
            <th :for={col <- @col} class={["px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase tracking-wider", col[:class]]}>
              {col.label}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-700/30">
          <tr :for={row <- @rows} class="hover:bg-slate-800/40 transition-colors">
            <td :for={col <- @col} class={["px-4 py-4 text-sm", col[:class]]}>
              {render_slot(col, row)}
            </td>
          </tr>
        </tbody>
      </table>
      <div :if={@rows == []} class="text-center py-12 text-slate-500">
        No blocks yet
      </div>
    </div>
    """
  end

  @doc """
  Renders an EthProofs link for a block number.
  """
  attr(:block_number, :integer, required: true)
  attr(:class, :string, default: nil)

  def ethproofs_link(assigns) do
    ~H"""
    <a
      href={"https://ethproofs.org/blocks/#{@block_number}"}
      target="_blank"
      rel="noopener noreferrer"
      class={[
        "text-cyan-400 hover:text-cyan-300 hover:underline font-mono",
        "inline-flex items-center gap-1",
        @class
      ]}
    >
      #{@block_number}
      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
      </svg>
    </a>
    """
  end

  @doc """
  Renders a hardware info card displaying system specifications.
  """
  attr(:hardware_info, :map, required: true)
  attr(:class, :string, default: nil)

  def hardware_info_card(assigns) do
    ~H"""
    <div class={[
      "bg-slate-800/60 border border-slate-700/50 rounded-xl p-5",
      @class
    ]}>
      <div class="flex items-center gap-3 mb-4">
        <div class="text-cyan-400">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
          </svg>
        </div>
        <h3 class="text-lg font-semibold text-white">Hardware</h3>
        <a
          href="https://ethproofs.org/clusters"
          target="_blank"
          rel="noopener noreferrer"
          class="ml-auto text-xs text-cyan-400 hover:text-cyan-300 hover:underline inline-flex items-center gap-1"
        >
          View cluster
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
          </svg>
        </a>
      </div>
      <div class="space-y-2 text-sm">
        <div class="flex justify-between">
          <span class="text-slate-400">CPU</span>
          <span class="text-slate-200 font-medium">{@hardware_info.cpu}</span>
        </div>
        <div class="flex justify-between">
          <span class="text-slate-400">Cores</span>
          <span class="text-slate-200 font-medium">{@hardware_info.cores}</span>
        </div>
        <div class="flex justify-between">
          <span class="text-slate-400">Memory</span>
          <span class="text-slate-200 font-medium">{@hardware_info.memory}</span>
        </div>
        <div class="flex justify-between">
          <span class="text-slate-400">OS</span>
          <span class="text-slate-200 font-medium">{@hardware_info.os}</span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a countdown timer for the next block.
  """
  attr(:seconds, :integer, required: true)
  attr(:class, :string, default: nil)

  def countdown(assigns) do
    ~H"""
    <div class={["text-center", @class]}>
      <div class="text-4xl font-bold text-white font-mono tabular-nums">
        {format_duration(@seconds)}
      </div>
      <div class="text-sm text-slate-400 mt-1">until next target block</div>
    </div>
    """
  end

  defp format_duration(seconds) when seconds < 0, do: "00:00"

  defp format_duration(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  @doc """
  Renders a flash message.
  """
  attr(:id, :string, doc: "the optional id of flash container")
  attr(:flash, :map, default: %{}, doc: "the map of flash messages to display")
  attr(:kind, :atom, values: [:info, :error], doc: "the kind of flash message")

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> JS.hide(transition: "opacity-0")}
      role="alert"
      class={[
        "fixed top-4 right-4 z-50 max-w-md p-4 rounded-lg shadow-lg cursor-pointer",
        @kind == :info && "bg-cyan-900/90 text-cyan-100 border border-cyan-700",
        @kind == :error && "bg-red-900/90 text-red-100 border border-red-700"
      ]}
    >
      <div class="flex items-center gap-3">
        <svg :if={@kind == :info} class="w-5 h-5 text-cyan-400" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
        </svg>
        <svg :if={@kind == :error} class="w-5 h-5 text-red-400" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
        </svg>
        <p class="text-sm font-medium">{msg}</p>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")
  attr(:id, :string, default: "flash-group", doc: "the optional id of flash container")

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end
end
