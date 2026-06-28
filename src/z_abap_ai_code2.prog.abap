REPORT z_abap_ai_code2.

"---------------------------------------------------------------------
" Z_ABAP_AI_CODE2 - new tool-based agent runner (OpenAI function calling)
"
" Runs in parallel to the legacy proto-tag flow:
"   legacy flow -> AGENTS folder (object_detector / task_orchestrator / ...)
"   this flow   -> TOOLS  folder (<tool_name>.json schemas + .md prompts)
"
" UI: same popup as the legacy program (copied as ZCL_CODE_POPUP2), but
" ASK_AI drives the agentic loop: prompt -> LLM with tools -> tool_calls
" -> ZCL_AI_TOOL_FACTORY -> ZCL_AITOOL_* -> results back -> final answer
"---------------------------------------------------------------------

DATA go_popup TYPE REF TO zcl_code_popup2.

" Provider key codes for the listbox; also passed straight to the API as the
" provider name (already upper-case, no provider_of() mapping needed).
TYPES ty_prov TYPE c LENGTH 12.
TYPES ty_name TYPE c LENGTH 30.

" Remembers the provider+key the model list was built for, so the live
" /v1/models call fires only when provider or key changes - not on every Enter.
DATA gv_loaded_key TYPE string.
" Random per-session salt. Folded into the cached model-list state so that state
" never holds the password in clear text (see AT SELECTION-SCREEN OUTPUT).
DATA gv_sess_salt TYPE string.
" Cached model listbox values - re-applied on every PBO so the list persists
" across screen round-trips (e.g. toggling the thinking checkbox).
DATA gt_model_vrm TYPE vrm_values.
" Set once the (mandatory) password has been entered and the first Enter was
" pressed: only then are the remaining fields revealed and a launch is allowed.
DATA gv_unlocked TYPE abap_bool.

SELECTION-SCREEN BEGIN OF BLOCK b_api WITH FRAME TITLE TEXT-001.
" Password is mandatory and comes first; everything else (MODIF ID DET) stays
" hidden until the password is entered and confirmed with Enter.
PARAMETERS: p_pwd    TYPE text255 OBLIGATORY,
            p_prov   TYPE ty_prov AS LISTBOX VISIBLE LENGTH 30
                     USER-COMMAND prov DEFAULT 'ANTHROPIC'     MODIF ID det,
            p_name   TYPE ty_name AS LISTBOX VISIBLE LENGTH 30
                     USER-COMMAND keys                         MODIF ID det,
            p_model  TYPE text255 AS LISTBOX VISIBLE LENGTH 45
                     MEMORY ID model                           MODIF ID det,
            p_tools  TYPE text255 OBLIGATORY                   MODIF ID det,
            p_temp   TYPE text10  DEFAULT '0.2'                MODIF ID det,
            p_maxt   TYPE i       DEFAULT 20000                MODIF ID det,
            p_nomax  AS CHECKBOX                               MODIF ID det,
            p_think  AS CHECKBOX                               MODIF ID det,
            p_thbud  TYPE i       DEFAULT 10000                MODIF ID det,
            p_log    TYPE text255                              MODIF ID det,
            " Wipe the password from memory after launch (recommended in PROD so
            " a debugger cannot read it). Uncheck on local/dev systems to avoid
            " re-typing it for each session.
            p_wipe   AS CHECKBOX DEFAULT 'X'                   MODIF ID det.
SELECTION-SCREEN END OF BLOCK b_api.

INITIALIZATION.
  p_tools = 'C:/soft/GITHUB/ABAP-AI-CODE/TOOLS'.
  p_log   = 'C:/temp/ABAP_AI_CODE/LOGS'.
  " Random salt for this run so the cached model-list state never stores the
  " password, not even hashed in a stable (offline-reusable) form.
  gv_sess_salt = cl_system_uuid=>create_uuid_c32_static( ).

  DATA lt_excl TYPE TABLE OF sy-ucomm.
  APPEND 'ONLI' TO lt_excl.
  CALL FUNCTION 'RS_SET_SELSCREEN_STATUS'
    EXPORTING  p_status  = sy-pfkey
    TABLES     p_exclude = lt_excl.

AT SELECTION-SCREEN OUTPUT.
  " Provider listbox values must be (re)set on every PBO, otherwise they are
  " lost after a round-trip and the selection does not stick. The text shows
  " the base URL the provider resolves to.
  DATA(lt_provs) = zcl_code_ai_api=>get_providers( ).
  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING id     = 'P_PROV'
              values = lt_provs.
  " Auto-select the usable provider. p_prov has DEFAULT 'ANTHROPIC' so it is
  " never empty - the real signal is whether the user has a key for the current
  " provider. If not, and they have keys for exactly one provider, switch to it
  " (overrides the default). This snaps a single-key user straight to their
  " provider; once they have a key for the selected provider, nothing changes.
  SELECT DISTINCT provider FROM zaicode_apikey
    INTO TABLE @DATA(lt_user_provs)
    WHERE username = @sy-uname.
  IF NOT line_exists( lt_user_provs[ provider = p_prov ] )
     AND lines( lt_user_provs ) = 1
     AND line_exists( lt_provs[ key = lt_user_provs[ 1 ]-provider ] ).
    p_prov = lt_user_provs[ 1 ]-provider.
  ELSEIF ( p_prov IS INITIAL OR NOT line_exists( lt_provs[ key = p_prov ] ) )
         AND lines( lt_provs ) = 1.
    p_prov = lt_provs[ 1 ]-key.
  ENDIF.

  " Key-name listbox: the encrypted keys this user stored for the provider
  " (entered via Z_ABAP_AI_KEYS). Only the name is shown - never the key.
  SELECT keyname FROM zaicode_apikey
    INTO TABLE @DATA(lt_names)
    WHERE username = @sy-uname AND provider = @p_prov
    ORDER BY keyname.
  DATA lt_name_vrm TYPE vrm_values.
  LOOP AT lt_names INTO DATA(ls_name).
    APPEND VALUE #( key = ls_name-keyname text = ls_name-keyname ) TO lt_name_vrm.
  ENDLOOP.
  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING id     = 'P_NAME'
              values = lt_name_vrm.
  " Auto-select the key name only when exactly one key is stored for this
  " user+provider. With several keys the user must choose, so an invalid/empty
  " selection is left blank rather than defaulting to an arbitrary first entry.
  IF p_name IS INITIAL OR NOT line_exists( lt_names[ keyname = p_name ] ).
    CLEAR p_name.
    IF lines( lt_names ) = 1.
      p_name = lt_names[ 1 ]-keyname.
    ENDIF.
  ENDIF.

  " Re-fetch the model list live only when provider, key name or password
  " changed; otherwise reuse the cached list (skipped on plain Enter). The
  " password is never kept in clear text here: it is folded into a per-session
  " salted SHA-256 token, so the cached state (GV_LOADED_KEY) cannot leak the
  " password to a debugger or a dump - even before P_WIPE clears P_PWD.
  DATA lv_pwd_tok TYPE string.
  cl_abap_message_digest=>calculate_hash_for_char(
    EXPORTING if_algorithm  = 'SHA-256'
              if_data       = |{ gv_sess_salt }{ p_pwd }|
    IMPORTING ef_hashstring = lv_pwd_tok ).
  DATA(lv_state) = |{ p_prov }\|{ p_name }\|{ lv_pwd_tok }|.
  IF p_name IS NOT INITIAL AND p_pwd IS NOT INITIAL AND gv_loaded_key <> lv_state.

    " Decrypt the chosen key with the entered password before listing models.
    DATA: lv_apikey TYPE string,
          lv_kerr   TYPE string.
    PERFORM decrypt_key USING p_prov p_name p_pwd
                        CHANGING lv_apikey lv_kerr.
    IF lv_kerr IS NOT INITIAL.
      CLEAR: gt_model_vrm, p_model, gv_loaded_key.
      MESSAGE lv_kerr TYPE 'W'.
    ELSE.

    DATA: lt_ids TYPE stringtab,
          lv_err TYPE string.
    zcl_code_ai_api=>list_models(
      EXPORTING i_url      = |{ zcl_code_ai_api=>base_url( CONV string( p_prov ) ) }/models|
                i_apikey   = lv_apikey
                i_provider = CONV string( p_prov )
      IMPORTING et_ids     = lt_ids
                e_error    = lv_err ).

    CLEAR gt_model_vrm.
    LOOP AT lt_ids INTO DATA(lv_id).
      APPEND VALUE #( key = lv_id text = lv_id ) TO gt_model_vrm.
    ENDLOOP.

    IF lt_ids IS NOT INITIAL.
      " Default to a haiku model when the current one is not in the new list.
      IF p_model IS INITIAL OR NOT line_exists( lt_ids[ table_line = p_model ] ).
        CLEAR p_model.
        LOOP AT lt_ids INTO lv_id WHERE table_line CS 'haiku'.
          p_model = lv_id.
          EXIT.
        ENDLOOP.
        IF p_model IS INITIAL.
          p_model = lt_ids[ 1 ].
        ENDIF.
      ENDIF.
      " Remember the loaded state only on success, so a failed call is retried.
      gv_loaded_key = lv_state.
    ELSE.
      " Fetch failed / empty: clear the stale model and surface the error.
      CLEAR p_model.
      IF lv_err IS NOT INITIAL.
        MESSAGE lv_err TYPE 'W'.
      ENDIF.
    ENDIF.
    ENDIF.
  ENDIF.

  " Model listbox values, like the provider list, must be set on every PBO.
  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING id     = 'P_MODEL'
              values = gt_model_vrm.

  " Screen visibility:
  "  - password (P_PWD) is always shown but masked (invisible input);
  "  - everything else (MODIF ID DET) stays hidden until the password is entered
  "    and confirmed with the first Enter (gv_unlocked);
  "  - the extended-thinking fields are hidden for non-Anthropic providers even
  "    once unlocked, since thinking is an Anthropic-only feature.
  DATA(lv_is_anth) = xsdbool( zcl_code_ai_api=>provider_of( CONV string( p_prov ) ) = 'ANTHROPIC' ).
  LOOP AT SCREEN.
    IF screen-name = 'P_PWD'.
      screen-invisible = '1'.
      MODIFY SCREEN.
    ELSEIF screen-group1 = 'DET'.
      IF gv_unlocked = abap_false.
        screen-active = '0'.
      ELSEIF ( screen-name CS 'P_THINK' OR screen-name CS 'P_THBUD' )
             AND lv_is_anth = abap_false.
        screen-active = '0'.
      ELSE.
        screen-active = '1'.
      ENDIF.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

AT SELECTION-SCREEN.
  CHECK sy-ucomm IS INITIAL OR sy-ucomm = 'UCCHECK'.

  " First Enter after the (mandatory) password has been entered just reveals the
  " rest of the screen - it does not launch yet.
  IF gv_unlocked = abap_false.
    gv_unlocked = abap_true.
    RETURN.
  ENDIF.

  " Launch the popup only once every required field is filled; otherwise just
  " stay on the screen (Enter still refreshes the model listbox above).
  IF p_name IS INITIAL OR p_model IS INITIAL.
    RETURN.
  ENDIF.

  " Decrypt the selected key with the entered password; a wrong password keeps
  " the user on the screen instead of starting a session with no key.
  DATA: lv_apikey TYPE string,
        lv_kerr   TYPE string.
  PERFORM decrypt_key USING p_prov p_name p_pwd
                      CHANGING lv_apikey lv_kerr.
  IF lv_kerr IS NOT INITIAL.
    MESSAGE lv_kerr TYPE 'E'.
    RETURN.
  ENDIF.

  " The key is now decrypted; the password is no longer needed. Wiping it shrinks
  " the debug blast radius to the single current key (not the master password).
  " Disabled by unchecking P_WIPE on local/dev systems.
  IF p_wipe = abap_true.
    CLEAR p_pwd.
  ENDIF.

  go_popup = NEW zcl_code_popup2(
    i_model       = p_model
    i_apikey      = lv_apikey
    i_provider    = CONV string( p_prov )
    i_agents_path = CONV string( p_tools )
    i_temperature = CONV string( p_temp )
    i_max_tokens  = COND i( WHEN p_nomax = 'X' THEN 0 ELSE p_maxt )
    " Extended thinking only applies to Anthropic-flavoured providers; 0 = off.
    i_thinking_budget = COND i( WHEN p_think = 'X'
                                 AND zcl_code_ai_api=>provider_of( CONV string( p_prov ) ) = 'ANTHROPIC'
                                THEN p_thbud ELSE 0 )
    i_log_path    = CONV string( p_log ) ).

  go_popup->show( ).

*----------------------------------------------------------------------*
* Read the encrypted key for (current user, provider, name) and decrypt
* it with the entered password. CV_ERR is filled when no key exists or
* the password is wrong; CV_KEY then stays empty.
*----------------------------------------------------------------------*
FORM decrypt_key USING uv_prov TYPE ty_prov
                       uv_name TYPE c
                       uv_pwd  TYPE clike
                 CHANGING cv_key TYPE string
                          cv_err TYPE string.

  CLEAR: cv_key, cv_err.

  SELECT SINGLE secret FROM zaicode_apikey
    INTO @DATA(lv_secret)
    WHERE username = @sy-uname
      AND provider = @uv_prov
      AND keyname  = @uv_name.
  IF sy-subrc <> 0 OR lv_secret IS INITIAL.
    cv_err = 'No stored key for this provider / name'.
    RETURN.
  ENDIF.

  TRY.
      cv_key = zcl_aicode_crypto=>decrypt(
        i_username = sy-uname
        i_provider = CONV string( uv_prov )
        i_name     = CONV string( uv_name )
        i_password = CONV string( uv_pwd )
        i_secret   = lv_secret ).
    CATCH cx_sec_sxml_encrypt_error.
      cv_err = 'Wrong password for the selected key'.
  ENDTRY.

ENDFORM.
