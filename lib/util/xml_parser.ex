defmodule Util.XmlParser do
  import SweetXml
  import Util.Log
  import TenbewGw
  @example_xml """
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

  def parse_asr(xml) do
    xml
    |> String.split("<soap:Body>")
    |> List.last
    |> String.split("</soap:Body>")
    |> List.first
    |> join_splits()
    |> parse
    |> fetch_result_map()
  end

  def process_asr(xml) do
    xml
    |> String.split("<soap:Body>")
    |> List.last
    |> String.split("</soap:Body>")
    |> List.first
    |> join_splits()
    |> parse
    |> fetch_result_map()
    |> return_asr_xml
  end

  def return_asr_xml(response) do
    result = response[:addSubscriptionResult]
    "addSubscriptionResult: #{inspect(result)}" |> color_info(:yellow)
    msisdn = result[:msisdn]
    serviceID = result[:serviceID]
    ccTid = result[:ccTID]
    """
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <ns2:getServicesResponse xmlns:ns2="http://wasp.doi.soap.protocol.WASP.co.za">
          <return>
            <serviceID>#{serviceID}</serviceID>
            <msisdn>#{msisdn}</msisdn>
            <Result>0</Result>
            <ccTid>#{ccTid}</ccTid>
          </return>
        </ns2:getServicesResponse>
      </soap:Body>
    </soap:Envelope>
    """
  end

  def parse_xml do
    @example_xml
    |> String.split("<soap:Body>")
    |> List.last
    |> String.split("</soap:Body>")
    |> List.first
    |> join_splits()
    |> parse
    |> fetch_result_map()
  end

  def return_xml_example do
    response = parse_xml
    result = response[:addSubscriptionResult]
    "addSubscriptionResult: #{inspect(result)}" |> color_info(:yellow)
    msisdn = result[:msisdn]
    serviceID = result[:serviceID]
    ccTid = result[:ccTID]
    """
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <ns2:getServicesResponse xmlns:ns2="http://wasp.doi.soap.protocol.WASP.co.za">
          <return>
            <serviceID>#{serviceID}</serviceID>
            <msisdn>#{msisdn}</msisdn>
            <Result>0</Result>
            <ccTid>#{ccTid}</ccTid>
          </return>
        </ns2:getServicesResponse>
      </soap:Body>
    </soap:Envelope>
    """
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

end
