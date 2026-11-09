"use strict";

const $ = (id) => document.getElementById(id);
const form = $("note-form");
const notesEl = $("notes");

async function api(path, options = {}) {
  const res = await fetch(`/api${path}`, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (res.status === 204) return null;
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || `Request failed (${res.status})`);
  return body;
}

function noteCard(note) {
  // Built with textContent (never innerHTML) so note text cannot inject HTML/JS.
  const card = document.createElement("article");
  card.className = "note";

  const h = document.createElement("h2");
  h.textContent = note.title;
  const p = document.createElement("p");
  p.textContent = note.content;

  const meta = document.createElement("div");
  meta.className = "meta";
  const when = document.createElement("span");
  when.textContent = `Updated ${new Date(note.updated_at).toLocaleString()}`;

  const buttons = document.createElement("div");
  const edit = document.createElement("button");
  edit.className = "secondary";
  edit.textContent = "Edit";
  edit.onclick = () => startEdit(note);
  const del = document.createElement("button");
  del.className = "danger";
  del.textContent = "Delete";
  del.onclick = () => removeNote(note.id);
  buttons.append(edit, del);

  meta.append(when, buttons);
  card.append(h, p, meta);
  return card;
}

async function loadNotes() {
  try {
    const notes = await api("/notes");
    notesEl.replaceChildren(...notes.map(noteCard));
    $("empty").hidden = notes.length > 0;
    $("error").textContent = "";
  } catch (err) {
    $("error").textContent = `Could not load notes: ${err.message}`;
  }
}

async function loadInfo() {
  try {
    const info = await api("/info");
    const el = $("served-by");
    el.textContent = "";
    el.append(
      "Served by ",
      Object.assign(document.createElement("code"), { textContent: info.instance_id }),
      ` in ${info.availability_zone} · version `,
      Object.assign(document.createElement("code"), { textContent: info.version }),
    );
  } catch {
    $("served-by").textContent = "API unreachable";
  }
}

function startEdit(note) {
  $("note-id").value = note.id;
  $("title").value = note.title;
  $("content").value = note.content;
  $("save-btn").textContent = "Save changes";
  $("cancel-btn").hidden = false;
  $("title").focus();
}

function resetForm() {
  form.reset();
  $("note-id").value = "";
  $("save-btn").textContent = "Add note";
  $("cancel-btn").hidden = true;
}

async function removeNote(id) {
  if (!confirm("Delete this note?")) return;
  try {
    await api(`/notes/${id}`, { method: "DELETE" });
    await loadNotes();
  } catch (err) {
    $("error").textContent = err.message;
  }
}

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  const id = $("note-id").value;
  const payload = JSON.stringify({ title: $("title").value, content: $("content").value });
  try {
    await api(id ? `/notes/${id}` : "/notes", { method: id ? "PUT" : "POST", body: payload });
    resetForm();
    await loadNotes();
  } catch (err) {
    $("error").textContent = err.message;
  }
});

$("cancel-btn").addEventListener("click", resetForm);
$("refresh-info").addEventListener("click", loadInfo);

loadNotes();
loadInfo();
