export function csrfToken() {
  const meta = document.querySelector("meta[name='csrf-token']")
  return meta ? meta.content : ""
}

export async function postJson(url, body = {}) {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-CSRF-Token": csrfToken()
    },
    credentials: "same-origin",
    body: JSON.stringify(body)
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) {
    const error = new Error(data.error || "request_failed")
    error.status = response.status
    error.data = data
    throw error
  }
  return data
}

export async function postFormData(url, formData) {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "X-CSRF-Token": csrfToken()
    },
    credentials: "same-origin",
    body: formData
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) {
    const error = new Error(data.error || "request_failed")
    error.status = response.status
    error.data = data
    throw error
  }
  return data
}
