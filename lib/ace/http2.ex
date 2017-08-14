defmodule Ace.HTTP2 do
  @moduledoc """
  **Hypertext Transfer Protocol Version 2 (HTTP/2)**

  > HTTP/2 enables a more efficient use of network
  > resources and a reduced perception of latency by introducing header
  > field compression and allowing multiple concurrent exchanges on the
  > same connection.  It also introduces unsolicited push of
  > representations from servers to clients.

  *Quote from [rfc 7540](https://tools.ietf.org/html/rfc7540).*
  """

  @doc """
  Transform an `Ace.Request` into a generic headers list.

  This headers list can be encoded via `Ace.HPack`.
  """
  def request_to_headers(request) do
    [
      {":scheme", Atom.to_string(request.scheme)},
      {":authority", "#{request.authority}"},
      {":method", Atom.to_string(request.method)},
      {":path", request.path} |
      request.headers
    ]
  end

  @doc """
  Transform an `Ace.Response` into a generic headers list.

  This headers list can be encoded via `Ace.HPack`.
  """
  def response_to_headers(request) do
    [
      {":status", Integer.to_string(request.status)} |
      request.headers
    ]
  end

  @doc """
  Build an `Ace.Request` from a decoded list of headers.

  Note the required pseudo-headers must be first.
  Request pseudo-headers are; `:scheme`, `:authority`, `:method` & `:path`.
  Duplicate or missing pseudo-headers will return an error.
  """
  def headers_to_request(headers, end_stream) do
    {:ok, request} = build_request(headers)
    {:ok, %{request | body: !end_stream}}
  end

  defp build_request(request_headers) do
    build_request(request_headers, {:scheme, :authority, :method, :path})
  end
  defp build_request([{":scheme", scheme} | rest], {:scheme, authority, method, path}) do
    case scheme do
      # DEBT can sent headers even be empty?
      "" ->
        {:error, {:protocol_error, "scheme must not be empty"}}
      _ ->
        build_request(rest, {scheme, authority, method, path})
    end
  end
  defp build_request([{":authority", authority} | rest], {scheme, :authority, method, path}) do
    case authority do
      "" ->
        {:error, {:protocol_error, "authority must not be empty"}}
      _ ->
        build_request(rest, {scheme, authority, method, path})
    end
  end
  defp build_request([{":method", method} | rest], {scheme, authority, :method, path}) do
    case method do
      "" ->
        {:error, {:protocol_error, "method must not be empty"}}
      _ ->
        build_request(rest, {scheme, authority, method, path})
    end
  end
  defp build_request([{":path", path} | rest], {scheme, authority, method, :path}) do
    case path do
      "" ->
        {:error, {:protocol_error, "path must not be empty"}}
      _ ->
        build_request(rest, {scheme, authority, method, path})
    end
  end
  defp build_request([{":" <> psudo, _value} | _rest], _required) do
    case psudo do
      psudo when psudo in ["scheme", "authority", "method", "path"] ->
        {:error, {:protocol_error, "pseudo-header sent more than once"}}
      other ->
        {:error, {:protocol_error, "unacceptable pseudo-header, :#{other}"}}
    end
  end
  defp build_request(headers, request = {scheme, authority, method, path}) do
    if scheme == :scheme or authority == :authority or method == :method or path == :path do
      {:error, {:protocol_error, "All pseudo-headers must be sent"}}
    else
      case read_headers(headers) do
        {:ok, headers} ->
          request = %Ace.Request{
            scheme: scheme,
            authority: authority,
            method: method,
            path: path,
            headers: headers,
            body: false
          }
          {:ok, request}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Build an `Ace.Response` from a decoded list of headers.

  Note the required pseudo-headers must be first.
  Response pseudo-headers are; `:status`.
  Duplicate or missing pseudo-headers will return an error.
  """
  def headers_to_response([{":status", status} | headers], end_stream) do
    case read_headers(headers) do
      {:ok, headers} ->
        {status, ""} = Integer.parse(status)
        {:ok, Ace.Response.new(status, headers, !end_stream)}
    end
  end

  @doc """
  Transform a list of decoded headers to a trailers structure.

  Note there are no required headers in a trailers set.
  """
  def headers_to_trailers(headers) do
    {:ok, headers} = read_headers(headers)
    %{headers: headers, end_stream: true}
  end

  defp read_headers(raw, acc \\ [])
  defp read_headers([], acc) do
    {:ok, Enum.reverse(acc)}
  end
  defp read_headers([{":"<>_,_} | _], _acc) do
    {:error, {:protocol_error, "pseudo-header sent amongst normal headers"}}
  end
  defp read_headers([{"connection", _} | _rest], _acc) do
    {:error, {:protocol_error, "connection header must not be used with HTTP/2"}}
  end
  defp read_headers([{"te", value} | rest], acc) do
    case value do
      "trailers" ->
        read_headers(rest, [{"te", value}, acc])
      _ ->
        {:error, {:protocol_error, "TE header field with any value other than 'trailers' is invalid"}}
    end
  end
  defp read_headers([{k, v} | rest], acc) do
    case String.downcase(k) == k do
      true ->
        read_headers(rest, [{k, v} | acc])
      false ->
        {:error, {:protocol_error, "headers must be lower case"}}
    end
  end

end
