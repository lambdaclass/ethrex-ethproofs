defmodule EthProofsClient.Notifications do
  @moduledoc false

  alias EthProofsClient.BlockMetadata
  alias EthProofsClient.Notifications.Slack
  alias EthProofsClient.Rpc

  @system_info_key {__MODULE__, :system_info}

  def input_generation_failed(block_number, reason) do
    notify_event(
      "Block #{block_number} input generation failed.",
      block_number,
      step: "input generation",
      reason: reason,
      status: :failure
    )
  end

  def proof_generation_failed(block_number, reason) do
    notify_event(
      "Block #{block_number} proof generation failed.",
      block_number,
      step: "proof generation",
      reason: reason,
      status: :failure
    )
  end

  def proof_data_failed(block_number, reason) do
    notify_event(
      "Block #{block_number} proof data read failed.",
      block_number,
      step: "proof data read",
      reason: reason,
      status: :failure
    )
  end

  def ethproofs_request_failed(block_number, endpoint, reason) do
    notify_event(
      "Block #{block_number} EthProofs #{endpoint} request failed.",
      block_number,
      step: "ethproofs #{endpoint} request",
      reason: reason,
      status: :failure
    )
  end

  def proof_submitted(block_number, proving_time_ms) do
    notify_event(
      "Block #{block_number} proved and submitted to EthProofs.",
      block_number,
      proving_time_ms: proving_time_ms,
      status: :success
    )
  end

  defp notify_event(message, block_number, opts) do
    if enabled?() do
      fields =
        []
        |> maybe_add_field("Step", opts[:step] && code_value(opts[:step]))
        |> maybe_add_field("Reason", opts[:reason] && code_value(format_reason(opts[:reason])))
        |> maybe_add_field("Proving time", format_proving_time(opts[:proving_time_ms]))
        |> add_block_fields(block_number)
        |> add_system_fields()

      headline = build_headline(message, opts[:status])
      notify(%{blocks: build_message_blocks(headline, fields)})
    else
      :ok
    end
  end

  defp build_headline(message, status) do
    emoji =
      case status do
        :success -> ":white_check_mark:"
        :failure -> ":warning:"
        _ -> nil
      end

    prefix = if is_binary(emoji), do: emoji <> " ", else: ""
    prefix <> message
  end

  defp add_block_fields(fields, block_number) do
    {gas_used, tx_count} =
      case BlockMetadata.get(block_number) do
        {:ok, %{gas_used: gas_used, tx_count: tx_count}} ->
          {Integer.to_string(gas_used), Integer.to_string(tx_count)}

        _ ->
          {"unknown", "unknown"}
      end

    fields
    |> add_field("Gas used", code_value(gas_used))
    |> add_field("Tx count", code_value(tx_count))
  end

  defp add_system_fields(fields) do
    info = system_info()

    fields
    |> add_field("GPU", code_value(info.gpu || "unknown"))
    |> add_field("CPU", code_value(info.cpu || "unknown"))
    |> add_field("RAM", code_value(info.ram || "unknown"))
    |> add_field("Branch & Commit", format_branch_commit(info))
  end

  defp add_field(fields, label, value), do: fields ++ [{label, value}]
  defp maybe_add_field(fields, _label, nil), do: fields
  defp maybe_add_field(fields, label, value), do: add_field(fields, label, value)

  defp format_proving_time(nil), do: nil

  defp format_proving_time(ms) when is_integer(ms) do
    seconds = Float.round(ms / 1000, 2)
    code_value("#{seconds}s")
  end

  defp format_proving_time(_), do: nil

  defp format_branch_commit(%{branch: branch, commit: commit}) do
    branch = branch || "unknown"
    commit = commit || "unknown"
    "#{code_value(branch)} (#{code_value(commit)})"
  end

  defp build_message_blocks(headline, fields) do
    blocks = [
      %{
        type: "header",
        text: %{type: "plain_text", text: headline, emoji: true}
      }
    ]

    case build_fields_text(fields) do
      "" -> blocks
      text -> blocks ++ [%{type: "section", text: %{type: "mrkdwn", text: text}}]
    end
  end

  defp build_fields_text(fields) do
    fields
    |> Enum.map(fn {label, value} -> "*#{label}:* #{value}" end)
    |> Enum.join("\n")
  end

  defp notify(message) do
    if enabled?() do
      Task.start(fn -> Slack.notify(message) end)
    end

    :ok
  end

  defp enabled? do
    slack_enabled?() and ethproofs_configured?()
  end

  defp slack_enabled? do
    case Application.get_env(:ethproofs_client, :slack_webhook) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  defp ethproofs_configured? do
    not blank?(Rpc.ethproofs_api_key()) and
      not blank?(Rpc.ethproofs_cluster_id()) and
      not blank?(Rpc.ethproofs_rpc_url())
  end

  defp blank?(value), do: is_nil(value) or value == ""

  defp code_value(value) when is_integer(value), do: "`#{value}`"
  defp code_value(value) when is_binary(value), do: "`#{value}`"
  defp code_value(value), do: "`#{inspect(value)}`"

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp system_info do
    case :persistent_term.get(@system_info_key, nil) do
      nil ->
        info = gather_system_info()
        :persistent_term.put(@system_info_key, info)
        info

      info ->
        info
    end
  end

  defp gather_system_info do
    %{
      cpu: cpu_info(),
      gpu: gpu_info(),
      ram: ram_info(),
      branch: git_branch(),
      commit: git_commit()
    }
  end

  defp cpu_info do
    case :os.type() do
      {:unix, :darwin} ->
        cmd_output("sysctl", ["-n", "machdep.cpu.brand_string"])

      {:unix, _} ->
        cpu_from_proc() || cpu_from_lscpu()

      _ ->
        nil
    end
  end

  defp gpu_info do
    nvidia =
      cmd_output("nvidia-smi", ["--query-gpu=name", "--format=csv,noheader"])

    cond do
      is_binary(nvidia) -> split_lines(nvidia)
      :os.type() == {:unix, :darwin} -> gpu_from_system_profiler()
      true -> gpu_from_lspci()
    end
  end

  defp ram_info do
    case :os.type() do
      {:unix, :darwin} ->
        with output when is_binary(output) <- cmd_output("sysctl", ["-n", "hw.memsize"]),
             {bytes, _} <- Integer.parse(output) do
          format_bytes(bytes)
        else
          _ -> nil
        end

      {:unix, _} ->
        ram_from_proc()

      _ ->
        nil
    end
  end

  defp git_branch do
    System.get_env("GIT_BRANCH") || git_cmd(["rev-parse", "--abbrev-ref", "HEAD"])
  end

  defp git_commit do
    System.get_env("GIT_COMMIT") || git_cmd(["rev-parse", "--short", "HEAD"])
  end

  defp cpu_from_proc do
    with {:ok, contents} <- File.read("/proc/cpuinfo"),
         [model] <- Regex.run(~r/^model name\s*:\s*(.+)$/m, contents, capture: :all_but_first) do
      String.trim(model)
    else
      _ -> nil
    end
  end

  defp cpu_from_lscpu do
    case cmd_output("lscpu", []) do
      nil ->
        nil

      output ->
        case Regex.run(~r/^Model name:\s*(.+)$/m, output, capture: :all_but_first) do
          [model] -> String.trim(model)
          _ -> nil
        end
    end
  end

  defp ram_from_proc do
    with {:ok, contents} <- File.read("/proc/meminfo"),
         [kb] <- Regex.run(~r/^MemTotal:\s+(\d+)\s+kB$/m, contents, capture: :all_but_first),
         {kb_int, _} <- Integer.parse(kb) do
      format_bytes(kb_int * 1024)
    else
      _ -> nil
    end
  end

  defp gpu_from_system_profiler do
    case cmd_output("system_profiler", ["SPDisplaysDataType"]) do
      nil ->
        nil

      output ->
        case Regex.scan(~r/Chipset Model:\s*(.+)/, output, capture: :all_but_first) do
          [] -> nil
          chips -> chips |> List.flatten() |> Enum.join(", ")
        end
    end
  end

  defp gpu_from_lspci do
    case cmd_output("lspci", []) do
      nil ->
        nil

      output ->
        gpus =
          output
          |> String.split("\n")
          |> Enum.filter(fn line ->
            String.contains?(line, "VGA compatible controller") or
              String.contains?(line, "3D controller")
          end)
          |> Enum.map(fn line ->
            line
            |> String.split(":", parts: 2)
            |> List.last()
            |> String.trim()
          end)

        case gpus do
          [] -> nil
          gpus -> Enum.join(gpus, ", ")
        end
    end
  end

  defp cmd_output(command, args) do
    case System.find_executable(command) do
      nil ->
        nil

      _ ->
        try do
          {output, status} = System.cmd(command, args, stderr_to_stdout: true)
          output = String.trim(output)
          if status == 0 and output != "", do: output, else: nil
        rescue
          _ -> nil
        end
    end
  end

  defp git_cmd(args) do
    case System.find_executable("git") do
      nil ->
        nil

      _ ->
        try do
          {output, status} = System.cmd("git", args, stderr_to_stdout: true)
          output = String.trim(output)
          if status == 0 and output != "", do: output, else: nil
        rescue
          _ -> nil
        end
    end
  end

  defp split_lines(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.join(", ")
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 ->
        format_unit(bytes, 1_073_741_824, "G")

      bytes >= 1_048_576 ->
        format_unit(bytes, 1_048_576, "M")

      bytes >= 1024 ->
        format_unit(bytes, 1024, "K")

      true ->
        "#{bytes}B"
    end
  end

  defp format_unit(bytes, divisor, unit) do
    value = bytes / divisor
    rounded = Float.round(value, 1)
    text = if rounded == trunc(rounded), do: Integer.to_string(trunc(rounded)), else: "#{rounded}"
    text <> unit
  end
end
