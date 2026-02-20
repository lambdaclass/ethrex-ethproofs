defmodule EthProofsClient.SystemInfo do
  @moduledoc """
  Gathers and caches system information (CPU, GPU, RAM, git info).
  Information is cached using :persistent_term for efficient repeated access.
  """

  @system_info_key {__MODULE__, :system_info}

  @doc """
  Returns cached system info map. Gathers and caches on first call.
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
  Gathers fresh system info without caching.
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

  @doc false
  def reset_cache do
    :persistent_term.erase(@system_info_key)
  rescue
    ArgumentError -> :ok
  end

  # --- CPU Detection ---

  defp cpu_info do
    case :os.type() do
      {:unix, :darwin} ->
        cmd_output("sysctl", ["-n", "machdep.cpu.brand_string"])

      {:unix, _linux} ->
        cpu_from_proc_cpuinfo() || cpu_from_lscpu()

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp cpu_from_proc_cpuinfo do
    case File.read("/proc/cpuinfo") do
      {:ok, content} ->
        case Regex.run(~r/model name\s*:\s*(.+)/, content) do
          [_, model] -> String.trim(model)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp cpu_from_lscpu do
    case cmd_output("lscpu", []) do
      nil ->
        nil

      output ->
        case Regex.run(~r/Model name:\s*(.+)/, output) do
          [_, model] -> String.trim(model)
          _ -> nil
        end
    end
  end

  # --- GPU Detection ---

  defp gpu_info do
    nvidia_gpu() || fallback_gpu()
  rescue
    _ -> nil
  end

  defp nvidia_gpu do
    cmd_output("nvidia-smi", ["--query-gpu=name", "--format=csv,noheader"])
  end

  defp fallback_gpu do
    case :os.type() do
      {:unix, :darwin} -> macos_gpu()
      {:unix, _linux} -> linux_gpu()
      _ -> nil
    end
  end

  defp linux_gpu do
    case cmd_output("lspci", []) do
      nil ->
        nil

      output ->
        gpus =
          output
          |> String.split("\n")
          |> Enum.filter(&(String.contains?(&1, "VGA compatible controller") or
                             String.contains?(&1, "3D controller")))
          |> Enum.map(fn line ->
            case String.split(line, ": ", parts: 2) do
              [_, name] -> String.trim(name)
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        case gpus do
          [] -> nil
          gpus -> Enum.join(gpus, ", ")
        end
    end
  end

  defp macos_gpu do
    case cmd_output("system_profiler", ["SPDisplaysDataType"]) do
      nil ->
        nil

      output ->
        case Regex.run(~r/Chipset Model:\s*(.+)/, output) do
          [_, model] -> String.trim(model)
          _ -> nil
        end
    end
  end

  # --- RAM Detection ---

  defp ram_info do
    case :os.type() do
      {:unix, :darwin} ->
        case cmd_output("sysctl", ["-n", "hw.memsize"]) do
          nil -> nil
          bytes_str -> format_bytes(String.to_integer(bytes_str))
        end

      {:unix, _linux} ->
        ram_from_proc_meminfo()

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp ram_from_proc_meminfo do
    case File.read("/proc/meminfo") do
      {:ok, content} ->
        case Regex.run(~r/MemTotal:\s*(\d+)\s*kB/, content) do
          [_, kb_str] ->
            bytes = String.to_integer(kb_str) * 1024
            format_bytes(bytes)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  # --- Git Detection ---

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

      executable ->
        case System.cmd(executable, args, stderr_to_stdout: true) do
          {output, 0} -> String.trim(output)
          _ -> nil
        end
    end
  rescue
    _ -> nil
  end

  defp git_cmd(args) do
    case System.find_executable("git") do
      nil ->
        nil

      git ->
        case System.cmd(git, args, stderr_to_stdout: true) do
          {output, 0} -> String.trim(output)
          _ -> nil
        end
    end
  rescue
    _ -> nil
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824 do
    "#{div(bytes, 1_073_741_824)}G"
  end

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    "#{div(bytes, 1_048_576)}M"
  end

  defp format_bytes(bytes) when bytes >= 1024 do
    "#{div(bytes, 1024)}K"
  end

  defp format_bytes(bytes) do
    "#{bytes}B"
  end
end
