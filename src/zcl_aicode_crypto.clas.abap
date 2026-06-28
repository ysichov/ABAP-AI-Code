class ZCL_AICODE_CRYPTO definition
  public
  create public .

*"* AES-256 encryption of provider API keys, bound to the SAP user.
*"*
*"* The AES key is derived from the user-supplied password AND sy-uname, so:
*"*  - the password is never stored anywhere (not in DB, not in source); a
*"*    developer reading the code or the table cannot decrypt without it;
*"*  - the username is part of the key and is also embedded in the plaintext,
*"*    so a foreign user cannot copy another row and pass it off under their
*"*    own name - decrypt() rejects a mismatching embedded username.
*"*
*"* Based on the documented cl_sec_sxml_writer AES pattern (SAP ABAP Central,
*"* "AES Encryption in ABAP"): encrypt_iv strips the leading IV block, decrypt
*"* prepends it again; payloads are converted string<->xstring and Base64-wrapped.
*"*
*"* Format versions (stored in SECRET):
*"*  - v1 (legacy, no prefix): deterministic IV, no salt, 50k key-stretch rounds.
*"*    Still decrypted for keys saved before the hardening; never written anymore.
*"*  - v2 ("v2:" prefix): random per-record salt + random IV, stronger stretching.
*"*    ENCRYPT always writes v2; re-saving a key in Z_ABAP_AI_KEYS upgrades it.
  public section.

    " Minimum password length enforced by the key-entry program. A longer
    " password is the other half of brute-force resistance (next to key
    " stretching) - it widens the search space an attacker must cover.
    constants C_MIN_PASSWORD_LENGTH type I value 10 ##NO_TEXT.

    " Encrypt I_APIKEY for (I_USERNAME, I_PROVIDER), protected by I_PASSWORD.
    " Returns the Base64 ciphertext to store in ZAICODE_APIKEY-SECRET.
    class-methods ENCRYPT
      importing
        !I_USERNAME     type SYUNAME
        !I_PROVIDER     type STRING
        !I_NAME         type STRING
        !I_PASSWORD     type STRING
        !I_APIKEY       type STRING
      returning
        value(R_SECRET) type STRING
      raising
        CX_SEC_SXML_ENCRYPT_ERROR .

    " Decrypt I_SECRET. Verifies the embedded user name equals I_USERNAME and
    " raises when it does not (wrong password -> garbage -> mismatch -> raise).
    class-methods DECRYPT
      importing
        !I_USERNAME     type SYUNAME
        !I_PROVIDER     type STRING
        !I_NAME         type STRING
        !I_PASSWORD     type STRING
        !I_SECRET       type STRING
      returning
        value(R_APIKEY) type STRING
      raising
        CX_SEC_SXML_ENCRYPT_ERROR .

  protected section.
  private section.

    " Separator between the embedded user name and the API key in the plaintext.
    constants C_SEP type C length 1 value cl_abap_char_utilities=>horizontal_tab ##NO_TEXT.

    " Key-stretching rounds: the AES key is hashed this many times so each
    " password guess costs an attacker C_KDF_ITERATIONS SHA-256 hashes, while the
    " legitimate user pays it once (~sub-second). Raise to harden, lower if the
    " one-time derivation feels slow on the app server.
    " C_KDF_ITERATIONS is the LEGACY (v1) count - kept only so old keys still
    " decrypt. New (v2) keys use the higher C_KDF_ITERATIONS_V2.
    constants C_KDF_ITERATIONS type I value 50000 ##NO_TEXT.
    constants C_KDF_ITERATIONS_V2 type I value 200000 ##NO_TEXT.

    " Marker prefixing a v2 SECRET. A stored value without it is a legacy v1 row.
    constants C_FMT_V2 type STRING value 'v2:' ##NO_TEXT.

    " 32-byte AES-256 key, stretched from ( password : username ). Never persisted.
    " I_SALT (v2) mixes a random per-record salt into the derivation so identical
    " passwords no longer yield identical keys; omitted for legacy v1 keys.
    " I_ITERATIONS selects the stretch count (v1 vs v2).
    class-methods DERIVE_KEY
      importing
        !I_PASSWORD   type STRING
        !I_USERNAME   type SYUNAME
        !I_SALT       type XSTRING optional
        !I_ITERATIONS type I default C_KDF_ITERATIONS
      returning
        value(R_KEY) type XSTRING .

    " 16-byte IV = first half of SHA-256( username : provider : name ).
    " Deterministic and not secret, but the key name makes the IV unique per
    " row so two keys of the same user+provider never share an IV.
    class-methods DERIVE_IV
      importing
        !I_USERNAME type SYUNAME
        !I_PROVIDER type STRING
        !I_NAME     type STRING
      returning
        value(R_IV) type XSTRING .
ENDCLASS.



CLASS ZCL_AICODE_CRYPTO IMPLEMENTATION.


  method DERIVE_KEY.

    " Initial hash of ( password : username ) -> 32 bytes (AES-256 key length).
    DATA(lv_seed) = |{ i_password }:{ i_username }|.
    DATA lv_x TYPE xstring.
    cl_abap_message_digest=>calculate_hash_for_char(
      EXPORTING if_algorithm = 'SHA-256'
                if_data      = lv_seed
      IMPORTING ef_hashx     = lv_x ).

    " Mix in the random per-record salt (v2 keys). Legacy v1 keys pass no salt,
    " so this block is skipped and the derivation stays bit-for-bit compatible.
    IF i_salt IS NOT INITIAL.
      DATA lv_salted TYPE xstring.
      CONCATENATE i_salt lv_x INTO lv_salted IN BYTE MODE.
      cl_abap_message_digest=>calculate_hash_for_raw(
        EXPORTING if_algorithm = 'SHA-256'
                  if_data      = lv_salted
        IMPORTING ef_hashx     = lv_x ).
    ENDIF.

    " Key stretching: re-hash the 32-byte value I_ITERATIONS times. This is a
    " one-time cost for the user but multiplies an attacker's brute-force effort
    " by the same factor (each password guess must repeat the whole chain).
    DATA lv_tmp TYPE xstring.
    DO i_iterations TIMES.
      cl_abap_message_digest=>calculate_hash_for_raw(
        EXPORTING if_algorithm = 'SHA-256'
                  if_data      = lv_x
        IMPORTING ef_hashx     = lv_tmp ).
      lv_x = lv_tmp.
    ENDDO.

    r_key = lv_x.

  endmethod.


  method DERIVE_IV.

    DATA lv_hashx TYPE xstring.
    DATA(lv_seed) = |{ i_username }:{ i_provider }:{ i_name }|.
    cl_abap_message_digest=>calculate_hash_for_char(
      EXPORTING if_algorithm  = 'SHA-256'
                if_data       = lv_seed
      IMPORTING ef_hashx      = lv_hashx ).
    " AES block size is 16 bytes - take the first half of the 32-byte hash.
    r_iv = lv_hashx(16).

  endmethod.


  method ENCRYPT.

    " v2 format: fresh random salt + random IV on every save, so two encryptions
    " of the same key never produce the same ciphertext and identical passwords
    " across users/records no longer derive the same AES key.
    DATA(lv_salt) = CONV xstring( cl_system_uuid=>create_uuid_x16_static( ) ).
    DATA(lv_iv)   = CONV xstring( cl_system_uuid=>create_uuid_x16_static( ) ).

    DATA(lv_key) = derive_key( i_password   = i_password
                               i_username   = i_username
                               i_salt       = lv_salt
                               i_iterations = c_kdf_iterations_v2 ).

    " Plaintext = "<username><TAB><apikey>" so decrypt can verify the owner.
    DATA(lv_plain) = |{ i_username }{ c_sep }{ i_apikey }|.

    DATA(lo_out) = cl_abap_conv_out_ce=>create( ).
    lo_out->write( data = lv_plain ).
    DATA(lv_plain_x) = lo_out->get_buffer( ).

    DATA lv_cipher TYPE xstring.
    cl_sec_sxml_writer=>encrypt_iv(
      EXPORTING plaintext  = lv_plain_x
                key        = lv_key
                iv         = lv_iv
                algorithm  = cl_sec_sxml_writer=>co_aes256_algorithm_pem
      IMPORTING ciphertext = lv_cipher ).

    " Store salt || ciphertext. The PEM ciphertext already carries the random IV
    " in its leading block, so it is kept as-is (no stripping) - the IV is no
    " longer re-derived on decrypt.
    DATA lv_blob TYPE xstring.
    CONCATENATE lv_salt lv_cipher INTO lv_blob IN BYTE MODE.

    DATA lv_b64 TYPE string.
    CALL FUNCTION 'SCMS_BASE64_ENCODE_STR'
      EXPORTING input  = lv_blob
      IMPORTING output = lv_b64.

    r_secret = c_fmt_v2 && lv_b64.

  endmethod.


  method DECRYPT.

    " v2 secrets carry the "v2:" marker; anything else is a legacy v1 row
    " (deterministic IV, no salt, 50k rounds) and is decrypted the old way.
    IF strlen( i_secret ) >= 3 AND i_secret(3) = c_fmt_v2.

      DATA lv_blob TYPE xstring.
      CALL FUNCTION 'SCMS_BASE64_DECODE_STR'
        EXPORTING input  = CONV string( i_secret+3 )
        IMPORTING output = lv_blob.

      " Split the leading 16-byte salt; the rest is the ciphertext, which still
      " carries its own IV block and is passed to decrypt unchanged.
      DATA(lv_salt_v2)   = lv_blob(16).
      DATA(lv_cipher_v2) = lv_blob+16.

      DATA(lv_key_v2) = derive_key( i_password   = i_password
                                    i_username   = i_username
                                    i_salt       = lv_salt_v2
                                    i_iterations = c_kdf_iterations_v2 ).

      DATA lv_plain_x2 TYPE xstring.
      cl_sec_sxml_writer=>decrypt(
        EXPORTING ciphertext = lv_cipher_v2
                  key        = lv_key_v2
                  algorithm  = cl_sec_sxml_writer=>co_aes256_algorithm_pem
        IMPORTING plaintext  = lv_plain_x2 ).

      DATA lv_plain2 TYPE string.
      cl_abap_conv_in_ce=>create( input = lv_plain_x2 )->read( IMPORTING data = lv_plain2 ).

      DATA lv_owner2 TYPE string.
      SPLIT lv_plain2 AT c_sep INTO lv_owner2 r_apikey.
      IF lv_owner2 <> i_username.
        RAISE EXCEPTION TYPE cx_sec_sxml_encrypt_error.
      ENDIF.
      RETURN.

    ENDIF.

    " --- Legacy v1 path (unchanged, kept for keys saved before hardening) ----
    DATA(lv_key) = derive_key( i_password = i_password i_username = i_username ).
    DATA(lv_iv)  = derive_iv( i_username = i_username i_provider = i_provider i_name = i_name ).

    DATA lv_body TYPE xstring.
    CALL FUNCTION 'SCMS_BASE64_DECODE_STR'
      EXPORTING input  = i_secret
      IMPORTING output = lv_body.

    " Re-attach the leading IV block that encrypt() stripped off.
    DATA lv_full TYPE xstring.
    CONCATENATE lv_iv lv_body INTO lv_full IN BYTE MODE.

    DATA lv_plain_x TYPE xstring.
    cl_sec_sxml_writer=>decrypt(
      EXPORTING ciphertext = lv_full
                key        = lv_key
                algorithm  = cl_sec_sxml_writer=>co_aes256_algorithm_pem
      IMPORTING plaintext  = lv_plain_x ).

    DATA lv_plain TYPE string.
    cl_abap_conv_in_ce=>create( input = lv_plain_x )->read( IMPORTING data = lv_plain ).

    " Split off the embedded owner and reject a substituted / foreign row.
    DATA lv_owner TYPE string.
    SPLIT lv_plain AT c_sep INTO lv_owner r_apikey.
    IF lv_owner <> i_username.
      RAISE EXCEPTION TYPE cx_sec_sxml_encrypt_error.
    ENDIF.

  endmethod.
ENDCLASS.
