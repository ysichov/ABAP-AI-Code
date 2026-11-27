REPORT z_cds_lxe_debug.

PARAMETERS: p_ddl   TYPE ddlname OBLIGATORY,
            p_from  TYPE lxeisolang LOWER CASE DEFAULT 'enUS' OBLIGATORY,
            p_to    TYPE lxeisolang LOWER CASE DEFAULT 'ukUA' OBLIGATORY,
            p_row   TYPE i DEFAULT 1,
            p_text  TYPE text255 LOWER CASE,
            p_write AS CHECKBOX,
            p_ro    AS CHECKBOX.

AT SELECTION-SCREEN.
  IF p_write = abap_true AND ( p_row < 1 OR p_text IS INITIAL ).
    MESSAGE 'Specify the row number and the new translation' TYPE 'E'.
  ENDIF.

START-OF-SELECTION.
  CONSTANTS: c_area TYPE lxecustmnr VALUE '999999',
             c_type TYPE lxeobjtype VALUE 'DDLS'.
  DATA lt_pairs TYPE STANDARD TABLE OF lxe_pcx_s1 WITH DEFAULT KEY.
  DATA lv_status TYPE lxestatprc.
  DATA lv_error TYPE lxestring.
  DATA(lv_object) = CONV lxeobjname( p_ddl ).
  DATA(lv_read_only) = xsdbool( p_write = abap_false OR p_ro = abap_true ).

  WRITE / |DDLS { lv_object } { p_from } -> { p_to } (client { sy-mandt })|.
  " Set the first debugger breakpoint here and step into the read with F5.
  CALL FUNCTION 'LXE_OBJ_TEXT_PAIR_READ'
    EXPORTING t_lang = p_to s_lang = p_from custmnr = c_area
              objtype = c_type objname = lv_object read_only = lv_read_only
    IMPORTING pstatus = lv_status err_msg = lv_error
    TABLES lt_pcx_s1 = lt_pairs.
  WRITE / |READ status={ lv_status } rows={ lines( lt_pairs ) } read_only={ lv_read_only } { lv_error }|.
  IF lv_status <> 'S'.
    RETURN.
  ENDIF.

  IF p_write = abap_false.
    LOOP AT lt_pairs INTO DATA(ls_pair).
      WRITE / |{ sy-tabix } { ls_pair-textkey } (limit { ls_pair-unitmlt })|.
      WRITE / |  { ls_pair-s_text } -> { ls_pair-t_text }|.
    ENDLOOP.
    RETURN.
  ENDIF.

  READ TABLE lt_pairs INDEX p_row ASSIGNING FIELD-SYMBOL(<pair>).
  IF sy-subrc <> 0.
    WRITE / 'Selected row does not exist'.
    RETURN.
  ENDIF.
  IF <pair>-unitmlt > 0 AND strlen( p_text ) > <pair>-unitmlt.
    WRITE / |Translation exceeds the limit of { <pair>-unitmlt } characters|.
    RETURN.
  ENDIF.
  IF <pair>-t_text = p_text.
    WRITE / 'The selected translation already has this value'.
    RETURN.
  ENDIF.

  WRITE / |Changing { <pair>-textkey }: { <pair>-t_text } -> { p_text }|.
  <pair>-t_text = p_text.
  CLEAR: lv_status, lv_error.
  " Set the second breakpoint here. SAP can commit inside the write FM.
  " Pass the complete pair table because empty targets may represent deletions.
  CALL FUNCTION 'LXE_OBJ_TEXT_PAIR_WRITE'
    EXPORTING t_lang = p_to s_lang = p_from custmnr = c_area
              objtype = c_type objname = lv_object
    IMPORTING pstatus = lv_status err_msg = lv_error
    TABLES lt_pcx_s1 = lt_pairs.
  WRITE / |WRITE status={ lv_status } { lv_error }|.
