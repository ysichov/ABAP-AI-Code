
REPORT z_abap_ai_code.

*----------------------------------------------------------------------*
* Global variables
*----------------------------------------------------------------------*
DATA go_popup TYPE REF TO zcl_code_popup.

SELECTION-SCREEN BEGIN OF BLOCK b_api WITH FRAME TITLE TEXT-001.
PARAMETERS: p_anth RADIOBUTTON GROUP api,
            p_oai  RADIOBUTTON GROUP api DEFAULT 'X'.

PARAMETERS: p_dest   TYPE text255 MEMORY ID dest,
            p_model  TYPE text255 MEMORY ID model,
            p_apikey TYPE text255 MEMORY ID api,
            p_agents TYPE text255 OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_api.

*----------------------------------------------------------------------*
* INITIALIZATION - suppress F8 (ONLI) button
*----------------------------------------------------------------------*
INITIALIZATION.
  p_agents = 'C:/soft/GITHUB/ABAP-AI-CODE/AGENTS'.

  DATA lt_excl TYPE TABLE OF sy-ucomm.
  APPEND 'ONLI' TO lt_excl.
  CALL FUNCTION 'RS_SET_SELSCREEN_STATUS'
    EXPORTING  p_status  = sy-pfkey
    TABLES     p_exclude = lt_excl.

*----------------------------------------------------------------------*
* AT SELECTION-SCREEN - open popup on Enter
*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
  CHECK sy-ucomm IS INITIAL OR sy-ucomm = 'UCCHECK'.

  go_popup = NEW zcl_code_popup(
    i_dest   = p_dest
    i_model  = p_model
    i_apikey = CONV string( p_apikey )
    i_provider = COND string( WHEN p_oai = 'X' THEN 'OPENAI' ELSE 'ANTHROPIC' )
    i_agents_path = CONV string( p_agents ) ).

  go_popup->show( ).

*----------------------------------------------------------------------*
* START-OF-SELECTION - never reached (F8 suppressed)
*----------------------------------------------------------------------*
START-OF-SELECTION.
