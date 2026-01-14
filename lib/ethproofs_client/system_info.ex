defmodule EthProofsClient.SystemInfo do
  @moduledoc """
  Gathers and caches system information (CPU, GPU, RAM, git info).

  Information is cached using :persistent_term for efficient repeated access.
  """

  @system_info_key {__MODULE__, :system_info}

  @doc """
  Returns cached system information. Gathers it on first call.
  """
  def get do
    case :persistent_term.get(@system_info_key, nil) do
      nil ->
        info = gather()
        :persistent_term.put(@system_info_key, info)
        info

      info ->
        info
    end
  end

  @doc """
  Gathers fresh system information without caching.
  """
  def gather do
    %{
      cpu: cpu_info(),
      gpu: gpu_info(),
      ram: ram_info(),
      branch: git_branch(),
      commit: git_commit()
    }
  end

  # --- CPU Info ---

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

  # --- GPU Info ---

  defp gpu_info do
    nvidia = cmd_output("nvidia-smi", ["--query-gpu=name", "--format=csv,noheader"])

    cond do
      is_binary(nvidia) -> split_lines(nvidia)
      :os.type() == {:unix, :darwin} -> gpu_from_system_profiler()
      true -> gpu_from_lspci()
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

  # --- RAM Info ---

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

  defp ram_from_proc do
    with {:ok, contents} <- File.read("/proc/meminfo"),
         [kb] <- Regex.run(~r/^MemTotal:\s+(\d+)\s+kB$/m, contents, capture: :all_but_first),
         {kb_int, _} <- Integer.parse(kb) do
      format_bytes(kb_int * 1024)
    else
      _ -> nil
    end
  end

  # --- Git Info ---

  defp git_branch do
    System.get_env("GIT_BRANCH") || git_cmd(["rev-parse", "--abbrev-ref", "HEAD"])
  end

  defp git_commit do
    System.get_env("GIT_COMMIT") || git_cmd(["rev-parse", "--short", "HEAD"])
  end

  # --- Helpers ---

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
