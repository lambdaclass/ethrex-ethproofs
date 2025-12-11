# defmodule EthProofsClient.Rpc do
#   @moduledoc false

#   use Tesla

#   plug(Tesla.Middleware.Headers, [{"content-type", "application/json"}])

#   def debug_execution_witness(block_number) do
#     send_request("debug_executionWitness", [block_number])
#   end

#   defp send_request(method, args) do
#     payload = build_payload(method, args)

#     {:ok, rsp} = post(Context.rpc_host(), payload)

#     handle_response(rsp)
#   end

#   defp build_payload(method, params) do
#     %{
#       jsonrpc: "2.0",
#       id: Enum.random(1..9_999_999),
#       method: method,
#       params: params
#     }
#     |> Jason.encode!()
#   end

#   defp handle_response(rsp) do
#     case Jason.decode!(rsp.body) do
#       %{"result" => result} ->
#         {:ok, result}

#       %{"error" => error} ->
#         {:error, error}
#     end
#   end
# end
