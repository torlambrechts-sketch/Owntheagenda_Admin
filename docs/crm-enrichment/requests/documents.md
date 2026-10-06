# Requests: Documents (Phase 5 screen build)

## Status

| Request | Status |
|---|---|
| R-DOCUMENTS-01 | Done in 0036 (`document_get.person.email`) · screen proposes the first signer |
| R-DOCUMENTS-02 | Open: needs a brand asset per product (storage) |
| R-DOCUMENTS-03 | Open: needs the edge functions (signed URL, upload) — with R-CAPTURE-01 |
| R-DOCUMENTS-04 | Open: needs a drive OAuth client and adapter |
| R-DOCUMENTS-05 | Open: only meaningful once a drive OAuth client exists; today «cannot be connected yet» is the true answer |

What the Documents screen needs beyond `0032_documents.sql`. None of it blocks the screen: each item is left out
or shown in its honest state until the change exists.

| ID | What | Why | Until then |
|---|---|---|---|
| R-DOCUMENTS-01 | `document_get` returns the addressed person's email (`person.email`) | The E-signature tab could propose the document's person as its first signer, and the link card could say who a link is for before it is made | Signers are added by name and email by hand |
| R-DOCUMENTS-02 | A brand mark per product (`products.mark` or an asset path) | Q12: a document carries its product's brand; the bundle has a mark for Orgpuls only | Orgpuls shows its mark; the other products show their colour tile and name (V-DOCUMENTS-05) |
| R-DOCUMENTS-03 | The edge function that signs `document_file_url`'s object (V-P5-06), and the upload function that stores a PDF under the deal before `document_upload` | Opening a stored PDF and uploading one (SF-33) | «Open PDF» reports the function as not deployed; no upload control |
| R-DOCUMENTS-04 | A way to list a staff member's drive folders (adapter) for `doc_storage_set_default`'s location | DOC-03: personal or shared location | The location select is disabled and shows the current default |
| R-DOCUMENTS-05 | `doc_template_import` answers with a message key for «your drive is not connected» distinct from «no OAuth client exists» | Today both read `not_connected` with the provider; the screen cannot tell a person to connect their drive from «drives cannot be connected yet» | The screen says drives cannot be connected yet, which is true today |
