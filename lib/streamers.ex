defmodule Streamers do
  require Record
  Record.defrecord :streamers, program_id: nil, path: nil, bandwidth: nil, ts_files: []

  @doc """
  Find streaming index file in the given directory.

  ## Examples

    iex> Streamers.find_index("this/doesnt/exist")
    nil

  """
  def find_index(directory) do
    files = Path.join(directory, "*.m3u8")
    if file = Enum.find Path.wildcard(files), &is_index?(&1) do
      file
    end
  end

  defp is_index?(file) do
    File.open! file, fn(pid) ->
      IO.read(pid, 25) == "#EXTM3U\n#EXT-X-STREAM-INF"
    end
  end

  @doc """
  Extract M3U8 records from the index file
  """
  def extract_m3u8(index_file) do
    File.open! index_file, fn(pid) ->
      # Discards #EXTM3U
      IO.read(pid, :line)
      do_extract_m3u8(pid, Path.dirname(index_file), [])
    end
  end

  defp do_extract_m3u8(pid, dir, acc) do
    case IO.read(pid, :line) do
      :eof -> Enum.reverse(acc)
      stream_inf ->
        path = IO.read(pid, :line)
        do_extract_m3u8(pid, dir, stream_inf, path, acc)
    end
  end

  defp do_extract_m3u8(pid, dir, stream_inf, path, acc) do
    #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=110000
    << "#EXT-X-STREAM-INF:PROGRAM-ID=", program_id, ",BANDWIDTH=", bandwidth :: binary >> = stream_inf
    path = Path.join(dir, path |> String.strip)
    { bandwidth, _ } = bandwidth |> String.strip |> Integer.parse
    record = streamers(program_id: program_id - ?0, path: path, bandwidth: bandwidth)
    do_extract_m3u8(pid, dir, [record|acc])
  end

  @doc """
  Process M3U8 records to get ts_files
  """
  def process_m3u8(m3u8s) do
    # Finished in 0.1 seconds (0.08s on load, 0.02s on tests)
    Enum.map m3u8s, &do_parallel_process_m3u8(&1, self)
    do_collect_m3u8(length(m3u8s), [])

    # Finished in 0.1 seconds (0.08s on load, 0.03s on tests)
    # Enum.map m3u8s, &do_process_m3u8(&1)
  end

  defp do_collect_m3u8(0, acc), do: acc

  defp do_collect_m3u8(count, acc) do
    receive do
      { :m3u8, updated_m3u8 } ->
        do_collect_m3u8(count - 1, [updated_m3u8|acc])
    end
  end

  defp do_parallel_process_m3u8(m3u8, parent_pid) do
    spawn_link(fn ->
      updated_m3u8 = do_process_m3u8(m3u8)
      send parent_pid, { :m3u8, updated_m3u8 }
    end)
  end

  defp do_process_m3u8(streamers(path: path) = m3u8) do
    File.open! path, fn(pid) ->
      # Discards #EXTM3U
      IO.read(pid, :line)
      # Discard #EXT-X-TARGETDURATION:15
      IO.read(pid, :line)

      streamers(m3u8, ts_files: do_process_m3u8(pid, []))
    end
  end

  defp do_process_m3u8(pid, acc) do
    case IO.read(pid, :line) do
      "#EXT-X-ENDLIST\n" -> Enum.reverse(acc)
      extinf when is_binary(extinf) -> # Discards EXTINF:10,
        # 8bda35243c7c0a7fc69ebe1383c6464c-00001.ts
        file = IO.read(pid, :line) |> String.strip
        do_process_m3u8(pid, [file|acc])
    end
  end
end
