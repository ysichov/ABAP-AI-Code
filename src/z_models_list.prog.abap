*&---------------------------------------------------------------------*
*& Report Z_MODELS_LIST
*&---------------------------------------------------------------------*
*& Список доступных моделей Anthropic API
*&---------------------------------------------------------------------*

REPORT z_models_list.

DATA: lt_models TYPE TABLE OF LINE,
      ls_model  TYPE LINE.

TYPES: BEGIN OF ty_model,
         model_id   TYPE string,
         name       TYPE string,
         max_tokens TYPE i,
         released   TYPE string,
       END OF ty_model.

DATA: lt_model_data TYPE TABLE OF ty_model,
      ls_model_data TYPE ty_model.

START-OF-SELECTION.

  PERFORM fill_models.
  PERFORM display_models.

FORM fill_models.

  CLEAR lt_model_data.

  ls_model_data-model_id = 'claude-opus-4-8'.
  ls_model_data-name = 'Opus 4.8'.
  ls_model_data-max_tokens = 20000.
  ls_model_data-released = '2025-01'.
  APPEND ls_model_data TO lt_model_data.

  ls_model_data-model_id = 'claude-sonnet-4-6'.
  ls_model_data-name = 'Sonnet 4.6'.
  ls_model_data-max_tokens = 200000.
  ls_model_data-released = '2024-07'.
  APPEND ls_model_data TO lt_model_data.

  ls_model_data-model_id = 'claude-haiku-4-5-20251001'.
  ls_model_data-name = 'Haiku 4.5'.
  ls_model_data-max_tokens = 8000.
  ls_model_data-released = '2025-10'.
  APPEND ls_model_data TO lt_model_data.

  ls_model_data-model_id = 'claude-fable-5'.
  ls_model_data-name = 'Fable 5'.
  ls_model_data-max_tokens = 4000.
  ls_model_data-released = '2025'.
  APPEND ls_model_data TO lt_model_data.

ENDFORM.

FORM display_models.

  WRITE: / 'Anthropic API доступні моделі'.
  WRITE: / '=' NO-GAP REPEAT 60.
  ULINE.

  LOOP AT lt_model_data INTO ls_model_data.
    WRITE: / ls_model_data-model_id,
             ls_model_data-name,
             ls_model_data-max_tokens,
             ls_model_data-released.
  ENDLOOP.

  ULINE.

ENDFORM.
