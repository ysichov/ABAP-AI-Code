*&---------------------------------------------------------------------*
*& Report Z_MODELS_LIST
*&---------------------------------------------------------------------*
*& Fetches the list of available models from the Anthropic API
*& (GET /v1/models) and displays them in an ALV grid.
*&---------------------------------------------------------------------*
REPORT z_models_list.

PARAMETERS: p_dest   TYPE rfcdest OBLIGATORY,            " RFC destination (SM59)
            p_apikey TYPE string  LOWER CASE OBLIGATORY, " API key
            p_anth   RADIOBUTTON GROUP prov DEFAULT 'X',  " Anthropic
            p_oai    RADIOBUTTON GROUP prov.              " OpenAI

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

    " Calls GET /v1/models; returns parsed models or fills e_error.
    " i_openai = 'X' switches auth/parsing to OpenAI, otherwise Anthropic.
    CLASS-METHODS fetch
      IMPORTING i_dest    TYPE rfcdest
                i_apikey  TYPE string
                i_openai  TYPE abap_bool DEFAULT abap_false
      EXPORTING et_models TYPE tt_model
                e_error   TYPE string.
ENDCLASS.

CLASS lcl_models IMPLEMENTATION.
  METHOD fetch.

    DATA lo_client TYPE REF TO if_http_client.

    cl_http_client=>create_by_destination(
      EXPORTING  destination           = i_dest
      IMPORTING  client                = lo_client
      EXCEPTIONS destination_not_found = 1
                 OTHERS                = 2 ).
    IF sy-subrc <> 0.
      e_error = |Destination { i_dest } not found (check SM59)|.
      RETURN.
    ENDIF.

    " The SM59 destination usually carries a path prefix (e.g. /v1/messages),
    " which ICF prepends. Read the resolved URI and point it at the models
    " endpoint: swap a "messages" segment for "models", else fall back to
    " /v1/models for a host-only destination.
    DATA(lv_uri) = lo_client->request->get_header_field( name = '~request_uri' ).
    IF lv_uri CS 'messages'.
      REPLACE ALL OCCURRENCES OF 'messages' IN lv_uri WITH 'models'.
    ELSE.
      lv_uri = '/v1/models'.
    ENDIF.
    lo_client->request->set_header_field( name = '~request_uri' value = lv_uri ).
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

    " Response shape: { "data": [ { "type":"model","id":..,"display_name":..,"created_at":.. } ], ... }
    TYPES: BEGIN OF ty_res,
             data TYPE tt_model,
           END OF ty_res.
    DATA ls_res TYPE ty_res.
    /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = ls_res ).

    IF ls_res-data IS INITIAL.
      DATA(lv_len) = nmin( val1 = strlen( lv_json ) val2 = 200 ).
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
    EXPORTING i_dest    = p_dest
              i_apikey  = p_apikey
    IMPORTING et_models = lt_models
              e_error   = lv_error ).

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
