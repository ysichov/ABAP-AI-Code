CLASS zcl_code_popup_data DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.

    " Slim replacement of AVE's ZCL_AVE_POPUP_DATA. The ported diff/ACR cluster
    " only calls these two. For an AI old-vs-new diff there is no SAP version
    " history or blame to read, so:
    "   get_user_name  - resolves the full name, falling back to the user id;
    "   get_ver_source - returns empty (the version-compare path is never used
    "                    here - diffs are driven by the two source strings).
    CLASS-METHODS get_user_name
      IMPORTING iv_user       TYPE versuser
      RETURNING VALUE(result) TYPE ad_namtext.

    CLASS-METHODS get_ver_source
      IMPORTING i_objtype     TYPE versobjtyp
                i_objname     TYPE versobjnam
                i_versno      TYPE versno
                i_korrnum     TYPE trkorr   OPTIONAL
                i_author      TYPE versuser OPTIONAL
                i_datum       TYPE versdate OPTIONAL
                i_zeit        TYPE verstime OPTIONAL
      RETURNING VALUE(result) TYPE abaptxt255_tab.

ENDCLASS.



CLASS zcl_code_popup_data IMPLEMENTATION.


  METHOD get_user_name.

    DATA lv_persno TYPE ad_persnum.

    SELECT SINGLE persnumber FROM usr21 INTO lv_persno
      WHERE bname = iv_user.
    IF sy-subrc = 0 AND lv_persno IS NOT INITIAL.
      SELECT SINGLE name_text FROM adrp INTO result
        WHERE persnumber = lv_persno.
    ENDIF.

    IF result IS INITIAL.
      result = iv_user.
    ENDIF.

  ENDMETHOD.


  METHOD get_ver_source.

    " No version source in the AI-diff context.
    CLEAR result.

  ENDMETHOD.

ENDCLASS.
