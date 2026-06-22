### read_sap_object

Fetches the current source code of an existing SAP object (program, class,
method, function module) straight from the system. It is a direct read tool: it
returns the source as the tool result and never modifies anything.

When to use:
- The user wants to view, describe, explain, document, list or analyse code.
- As a mandatory prerequisite before modify_sap_object or review_sap_code for the
  same object (READ before MODIFY / REVIEW).

Arguments:
- object_type: one of PROG, CLAS, METH, FUNC, REPS, OTHER.
- object_name: technical name, e.g. 'ZCL_TEST', 'ZCL_TEST=>METHOD_NAME',
  'Z_PROGRAM'. Supports a wildcard pattern to list matching objects
  (e.g. 'ZCL_AITOOL_*') and a comma-separated list to read several objects in one
  call (e.g. 'ZCL_A, ZCL_B, ZCL_C').

Notes:
- If the object is not found the tool reports an error - do not retry with a
  guessed name and do not invent source code.
