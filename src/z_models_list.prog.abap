*&---------------------------------------------------------------------*
*& Report Z_MODELS_LIST
*&---------------------------------------------------------------------*
*& Fetches the list of available models from the Anthropic API
*& (GET /v1/models) and displays them in an ALV grid.
*&---------------------------------------------------------------------*
REPORT z_models_list.

PARAMETERS: p_dest   TYPE rfcdest OBLIGATORY,           " RFC destination (SM59) -> api.anthropic.com
            p_apikey TYPE string  LOWER CASE OBLIGATORY. " Anthropic API key

*&---------------------------------------------------------------------*
*& Local class: thin wrapper around the /v1/models endpoint
*&---------------------------------------------------------------------*
CLASS lcl_models DEFINITION.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_model,
             id           TYPE string,
             display_name TYPE string,
             created_at   TYPE string,
           END OF ty_model,
           tt_model TYPE STANDARD TABLE OF ty_model WITH DEFAULT KEY.

    " Calls GET /v1/models; returns parsed models or fills e_error.
    CLASS-METHODS fetch
      IMPORTING i_dest    TYPE rfcdest
                i_apikey  TYPE string
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

    " Override the path so we hit /v1/models regardless of the SM59 path prefix.
    cl_http_utility=>set_request_uri( request = lo_client->request
                                      uri     = '/v1/models' ).
    lo_client->request->set_method( 'GET' ).
    lo_client->request->set_header_field( name = 'anthropic-version' value = '2023-06-01' ).
    lo_client->request->set_header_field( name = 'x-api-key'         value = i_apikey ).

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
      e_error = |Empty / unexpected response: { lv_json+0(200) }|.
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
