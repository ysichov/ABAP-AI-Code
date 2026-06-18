*&---------------------------------------------------------------------*
*& Report Z_MODELS_LIST
*&---------------------------------------------------------------------*
*& Fetches the list of available models from an LLM provider
*& (GET /v1/models) and displays them in an ALV grid.
*& Calls the API directly via create_by_url - no SM59 destination needed.
*&---------------------------------------------------------------------*
REPORT z_models_list.

PARAMETERS: p_url   TYPE string LOWER CASE OBLIGATORY
                    DEFAULT 'https://api.anthropic.com/v1/models',
            p_apikey TYPE string LOWER CASE OBLIGATORY,        " API key
            p_anth  RADIOBUTTON GROUP prov DEFAULT 'X',        " Anthropic auth/parsing
            p_oai   RADIOBUTTON GROUP prov,                    " OpenAI-compatible auth/parsing
            p_pxhost TYPE string LOWER CASE,                   " optional proxy host
            p_pxport TYPE string LOWER CASE,                   " optional proxy service/port
            p_sslid TYPE ssfapplssl DEFAULT 'ANONYM'.          " SSL client identity (STRUST)

*&---------------------------------------------------------------------*
*& Local class: thin wrapper around the /v1/models endpoint
*&---------------------------------------------------------------------*
CLASS lcl_models DEFINITION.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_model,
             id           TYPE string,
             display_name TYPE string,  " Anthropic
             created_at   TYPE string,  " Anthropic
             created      TYPE string,  " OpenAI (unix ts)
             owned_by     TYPE string,  " OpenAI
           END OF ty_model,
           tt_model TYPE STANDARD TABLE OF ty_model WITH DEFAULT KEY.

    " Calls GET <i_url> directly (create_by_url, no SM59).
    " i_openai = 'X' switches auth/parsing to OpenAI, otherwise Anthropic.
    CLASS-METHODS fetch
      IMPORTING i_url       TYPE string
                i_apikey    TYPE string
                i_openai    TYPE abap_bool   DEFAULT abap_false
                i_ssl_id    TYPE ssfapplssl  DEFAULT 'ANONYM'
                i_proxy_host TYPE string     OPTIONAL
                i_proxy_svc  TYPE string     OPTIONAL
      EXPORTING et_models   TYPE tt_model
                e_error     TYPE string.
ENDCLASS.

CLASS lcl_models IMPLEMENTATION.
  METHOD fetch.

    DATA lo_client TYPE REF TO if_http_client.

    cl_http_client=>create_by_url(
      EXPORTING  url                = i_url
                 ssl_id             = i_ssl_id
                 proxy_host         = i_proxy_host
                 proxy_service      = i_proxy_svc
      IMPORTING  client             = lo_client
      EXCEPTIONS argument_not_found = 1
                 plugin_not_active  = 2
                 internal_error     = 3
                 OTHERS             = 4 ).
    IF sy-subrc <> 0.
      e_error = |create_by_url failed rc={ sy-subrc } (check URL / SSL in STRUST)|.
      RETURN.
    ENDIF.

    lo_client->request->set_method( 'GET' ).
    IF i_openai = abap_true.
      lo_client->request->set_header_field( name = 'Authorization' value = |Bearer { i_apikey }| ).
    ELSE.
      lo_client->request->set_header_field( name = 'anthropic-version' value = '2023-06-01' ).
      lo_client->request->set_header_field( name = 'x-api-key'         value = i_apikey ).
    ENDIF.

    " Suppress the SAP logon popup so a 401/403 returns the JSON body instead
    " of prompting the user for a password.
    lo_client->propertytype_logon_popup = if_http_client=>co_disabled.

    lo_client->send( EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    IF sy-subrc <> 0.
      e_error = 'HTTP send failed'.
      RETURN.
    ENDIF.

    lo_client->receive( EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    IF sy-subrc <> 0.
      e_error = 'HTTP receive failed'.
      RETURN.
    ENDIF.

    DATA(lv_json) = lo_client->response->get_cdata( ).

    " Response shape (both Anthropic and OpenAI-compatible):
    "   { "data": [ { "id":.., "display_name":.., ... } ], ... }
    TYPES: BEGIN OF ty_res,
             data TYPE tt_model,
           END OF ty_res.
    DATA ls_res TYPE ty_res.
    /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = ls_res ).

    IF ls_res-data IS INITIAL.
      DATA(lv_len) = nmin( val1 = strlen( lv_json ) val2 = 300 ).
      e_error = |Empty / unexpected response: { lv_json(lv_len) }|.
      RETURN.
    ENDIF.

    et_models = ls_res-data.

  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
START-OF-SELECTION.

  DATA: lt_models TYPE lcl_models=>tt_model,
        lv_error  TYPE string.

  lcl_models=>fetch(
    EXPORTING i_url        = p_url
              i_apikey     = p_apikey
              i_openai     = p_oai
              i_ssl_id     = p_sslid
              i_proxy_host = p_pxhost
              i_proxy_svc  = p_pxport
    IMPORTING et_models    = lt_models
              e_error      = lv_error ).

  IF lv_error IS NOT INITIAL.
    MESSAGE lv_error TYPE 'I'.
    RETURN.
  ENDIF.

  cl_salv_table=>factory(
    IMPORTING r_salv_table = DATA(lo_alv)
    CHANGING  t_table      = lt_models ).
  lo_alv->get_functions( )->set_all( ).
  lo_alv->get_columns( )->set_optimize( ).
  lo_alv->display( ).
