REPORT z_abap_ai_keys.

"---------------------------------------------------------------------
" Z_ABAP_AI_KEYS - enter / update the LLM provider API key for the
" current SAP user. The key is stored AES-256 encrypted in ZAICODE_APIKEY,
" with the encryption key derived from a password that is never stored.
"
" Security:
"  - The password is the key: without it nobody (not even a developer who
"    reads this source or the table) can decrypt the API key.
"  - The key is bound to sy-uname, so a foreign user cannot reuse another
"    user's encrypted row under their own name.
"  - "Password to run": a wrong password is detected by trying to decrypt an
"    existing row of this user; on failure the program refuses to save.
"---------------------------------------------------------------------

TYPES ty_prov TYPE c LENGTH 12.

SELECTION-SCREEN BEGIN OF BLOCK b_api WITH FRAME TITLE TEXT-001.
PARAMETERS: p_prov TYPE ty_prov AS LISTBOX VISIBLE LENGTH 30
                   USER-COMMAND prov DEFAULT 'ANTHROPIC',
            p_name TYPE c LENGTH 30 DEFAULT 'DEFAULT',
            p_key  TYPE text255,
            p_pwd  TYPE text255,
            p_pwd2 TYPE text255.
SELECTION-SCREEN END OF BLOCK b_api.

INITIALIZATION.
  " Seed the provider customizing table on first use so the dropdown is never
  " empty. Only runs when the table has no rows yet - later edits are kept.
  SELECT SINGLE @abap_true FROM zaicode_provider INTO @DATA(lv_exists).
  IF sy-subrc <> 0.
    INSERT zaicode_provider FROM TABLE @( VALUE #(
      ( provider = 'ANTHROPIC'  url = 'https://api.anthropic.com/v1' anthropic = abap_true )
      ( provider = 'OPENAI'     url = 'https://api.openai.com/v1' cachekey = abap_true )
      ( provider = 'MISTRAL'    url = 'https://api.mistral.ai/v1' )
      ( provider = 'GEMINI'     url = 'https://generativelanguage.googleapis.com/v1beta/openai' )
      ( provider = 'GROQ'       url = 'https://api.groq.com/openai/v1' )
      ( provider = 'CEREBRAS'   url = 'https://api.cerebras.ai/v1' )
      ( provider = 'OPENROUTER' url = 'https://openrouter.ai/api/v1' )
      ( provider = 'NVIDIA'     url = 'https://integrate.api.nvidia.com/v1' ) ) ).
    IF sy-subrc = 0.
      COMMIT WORK.
    ENDIF.
  ENDIF.

AT SELECTION-SCREEN OUTPUT.
  " Provider listbox - re-set on every PBO so the selection sticks. Filled from
  " the customizing table ZAICODE_PROVIDER (maintained by hand in SM30/SE16).
  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING id     = 'P_PROV'
              values = zcl_code_ai_api=>get_providers( ).

  " Mask both password fields (invisible input).
  LOOP AT SCREEN.
    IF screen-name = 'P_PWD' OR screen-name = 'P_PWD2'.
      screen-invisible = '1'.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

START-OF-SELECTION.

  " --- Basic input validation ---------------------------------------------
  IF p_pwd IS INITIAL.
    MESSAGE 'Enter a password' TYPE 'E'.
  ENDIF.
  IF strlen( p_pwd ) < zcl_aicode_crypto=>c_min_password_length.
    MESSAGE |Password must be at least { zcl_aicode_crypto=>c_min_password_length } characters| TYPE 'E'.
  ENDIF.
  IF p_pwd <> p_pwd2.
    MESSAGE 'Passwords do not match' TYPE 'E'.
  ENDIF.
  IF p_key IS INITIAL.
    MESSAGE 'Enter an API key' TYPE 'E'.
  ENDIF.
  IF p_name IS INITIAL.
    MESSAGE 'Enter a key name' TYPE 'E'.
  ENDIF.

  " --- Password gate ------------------------------------------------------
  " If this user already has an encrypted row, the password must decrypt it;
  " otherwise this is the user's first key and the password is established now.
  DATA: lv_prov_e   TYPE zaicode_apikey-provider,
        lv_name_e   TYPE zaicode_apikey-keyname,
        lv_secret_e TYPE zaicode_apikey-secret.
  SELECT provider keyname secret FROM zaicode_apikey
    INTO (lv_prov_e, lv_name_e, lv_secret_e)
    UP TO 1 ROWS
    WHERE username = sy-uname.
  ENDSELECT.
  IF sy-subrc = 0 AND lv_secret_e IS NOT INITIAL.
    TRY.
        zcl_aicode_crypto=>decrypt(
          i_username = sy-uname
          i_provider = CONV string( lv_prov_e )
          i_name     = CONV string( lv_name_e )
          i_password = CONV string( p_pwd )
          i_secret   = lv_secret_e ).
      CATCH cx_sec_sxml_encrypt_error.
        MESSAGE 'Wrong password - cannot proceed' TYPE 'E'.
    ENDTRY.
  ENDIF.

  " --- Encrypt and store --------------------------------------------------
  DATA lv_secret TYPE string.
  TRY.
      lv_secret = zcl_aicode_crypto=>encrypt(
        i_username = sy-uname
        i_provider = CONV string( p_prov )
        i_name     = CONV string( p_name )
        i_password = CONV string( p_pwd )
        i_apikey   = CONV string( p_key ) ).
    CATCH cx_sec_sxml_encrypt_error INTO DATA(lx_enc).
      MESSAGE |Encryption failed: { lx_enc->get_text( ) }| TYPE 'E'.
  ENDTRY.

  DATA ls_row TYPE zaicode_apikey.
  ls_row-mandt    = sy-mandt.
  ls_row-username = sy-uname.
  ls_row-provider = p_prov.
  ls_row-keyname  = p_name.
  ls_row-secret   = lv_secret.
  MODIFY zaicode_apikey FROM ls_row.
  IF sy-subrc = 0.
    COMMIT WORK.
    MESSAGE |API key '{ p_name }' for { p_prov } saved (encrypted)| TYPE 'S'.
  ELSE.
    ROLLBACK WORK.
    MESSAGE 'Save failed' TYPE 'E'.
  ENDIF.
