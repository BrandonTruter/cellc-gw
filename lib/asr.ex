defmodule ASR do
  @example """
  <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
    <SOAP-ENV:Header xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
      <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" soap:mustUnderstand="1">
        <wsse:UsernameToken wsu:Id="UsernameToken-583283">
          <wsse:Username>tenbew</wsse:Username>
          <wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText">tenbew678</wsse:Password>
        </wsse:UsernameToken>
      </wsse:Security>
    </SOAP-ENV:Header>
    <soap:Body>
      <ns2:addSubscriptionResult xmlns:ns2="http://wasp.doi.soap.protocol.cellc.co.za" xmlns:ns3="http://doi.net.cellc.co.za">
        <serviceID>5114049456</serviceID>
        <msisdn>27621302071</msisdn>
        <serviceName>Gaming</serviceName>
        <contentProvider>QQ</contentProvider>
        <smsSent>Confirm your request for QQ Gaming @R5.00 per day. Reply "Yes" to confirm/"No" to cancel. Free SMS</smsSent>
        <smsReply>Yes</smsReply>
        <subscriptionTime></subscriptionTime>
        <waspReference>00</waspReference>
        <status>ACTIVE</status>
        <ccTID>863282451</ccTID>
      </ns2:addSubscriptionResult>
    </soap:Body>
  </soap:Envelope>
  """
  import SweetXml
  def parse_example do
    @example
    |> String.split("<soap:Body>")
    |> List.last
    |> String.split("</soap:Body>")
    |> List.first
    |> join_splits()
    |> parse
    |> fetch_result_map()
    |> IO.inspect
  end

  defp join_splits(str) do
    "<soapenv:Body>" <> str <> "</soapenv:Body>"
  end

  defp fetch_result_map(doc) do
    doc |> xmap(
      addSubscriptionResult: [
        ~x"./ns2:addSubscriptionResult"o,
        serviceID: ~x"./serviceID/text()"s,
        msisdn: ~x"./msisdn/text()"s,
        contentProvider: ~x"./contentProvider/text()"s,
        smsSent: ~x"./smsSent/text()"s,
        smsReply: ~x"./smsReply/text()"s,
        subscriptionTime: ~x"./subscriptionTime/text()"s,
        waspReference: ~x"./waspReference/text()"s,
        status: ~x"./status/text()"s,
        ccTID: ~x"./ccTID/text()"s
      ]
    )
  end

  # mix run -e ASR.parse_example

  # %{
  #   addSubscriptionResult: %{
  #     ccTID: "863282451",
  #     contentProvider: "QQ",
  #     msisdn: "27621302071",
  #     serviceID: "5114049456",
  #     smsReply: "Yes",
  #     smsSent: "Confirm your request for QQ Gaming @R5.00 per day. Reply \"Yes\" to confirm/\"No\" to cancel. Free SMS",
  #     status: "ACTIVE",
  #     subscriptionTime: "",
  #     waspReference: "00"
  #   }
  # }
end
