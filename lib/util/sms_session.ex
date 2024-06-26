# defmodule Util.SmsSession do
#   use SMPPEX.Session
#   import Util.Log
#   require Logger
#
#   @from {"from", 1, 1}
#   @to {"to", 1, 1}
#   @message "Welcome to QQ-Tenbew Games. Experience our world. Thank you for subscribing. Service costs 5 Rands a day charged daily"
#
#   # Need these from Leelan
#   @system_id "system_id"
#   @password "password"
#
#   # This ESME does the following:
#   #   1. Receives port number and three arguments:
#   #       waiting_pid — a pid of the process which will be informed when ESME stops;
#   #       count — count of PDUs to send;
#   #       window — window size, the maximum number of sent PDU’s without resps.
#   #   2. Connects to the specified port on localhost and issues a bind command.
#   #   3. Starts to send predefined PDUs after bind at maximum possible rate but regarding window size.
#   #   4. Stops after all PDUs are sent and notifies the waiting process.
#
#   # Usage:
#     # {:ok, esme} = SmsSession.start_link(host, port)
#     # SMPPEX.Session.send_pdu(esme, SMPPEX.Pdu.Factory.bind_transmitter("system_id", "password"))
#
#   def start_link(port, waiting_pid, count, window) do
#     SMPPEX.ESME.start_link("127.0.0.1", port, {__MODULE__, [waiting_pid, count, window]})
#   end
#
#   def start_link(host, port) do
#     SMPPEX.ESME.start_link(host, port, {__MODULE__, []})
#   end
#
#   def init(_, _, [waiting_pid, count, window]) do
#     Kernel.send(self(), :bind)
#     {:ok, %{waiting_pid: waiting_pid, count_to_send: count, count_waiting_resp: 0, window: window}}
#   end
#
#   def handle_resp(pdu, _original_pdu, st) do
#     case SMPPEX.Pdu.command_name(pdu) do
#       :submit_sm_resp ->
#         new_st = %{ st | count_waiting_resp: st.count_waiting_resp - 1 }
#         send_pdus(new_st)
#       :bind_transmitter_resp ->
#         send_pdus(st)
#       _ ->
#         {:ok, st}
#     end
#   end
#
#   def handle_resp_timeout(pdu, st) do
#     "PDU timeout: #{inspect pdu}, terminating" |> color_info(:red)
#     # Logger.error("PDU timeout: #{inspect pdu}, terminating")
#     {:stop, :resp_timeout, st}
#   end
#
#   def terminate(reason, _, st) do
#     "ESME stopped with reason #{inspect reason}" |> color_info(:lightred)
#     # Logger.info("ESME stopped with reason #{inspect reason}")
#     Kernel.send(st.waiting_pid, {self(), :done})
#     :stop
#   end
#
#   def handle_info(:bind, st) do
#     {:noreply, [SMPPEX.Pdu.Factory.bind_transmitter(@system_id, @password)], st}
#   end
#
#   defp send_pdus(st) do
#     cond do
#       st.count_to_send > 0 ->
#         count_to_send = min(st.window - st.count_waiting_resp, st.count_to_send)
#         new_st = %{ st | count_waiting_resp: st.window, count_to_send: st.count_to_send - count_to_send }
#         {:ok, make_pdus(count_to_send), new_st}
#       st.count_waiting_resp > 0 ->
#         {:ok, st}
#       true ->
#         "All PDUs sent, all resps received, terminating" |> color_info(:yellow)
#         # Logger.info("All PDUs sent, all resps received, terminating")
#         {:stop, :normal, st}
#     end
#   end
#
#   defp make_pdus(0), do: []
#   defp make_pdus(n) do
#     for _ <- 1..n, do: SMPPEX.Pdu.Factory.submit_sm(@from, @to, @message)
#   end
#
# end
