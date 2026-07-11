// ── Element references ────────────────────────────────────────
// (All IDs below must remain exactly as-is — used by fetch/gallery logic)
const uploadBtn    = document.getElementById("uploadBtn");
const imageInput   = document.getElementById("imageInput");
const status       = document.getElementById("status");
const processType  = document.getElementById("processType");
const previewImage = document.getElementById("previewImage");
const previewEmpty = document.getElementById("previewEmpty");
const gallery      = document.getElementById("gallery");

// ── File input: show chosen filename + live preview ────────────
const fileChosen = document.getElementById("fileChosen");
let prevObjectUrl = null;

imageInput.addEventListener("change", () => {
    const file = imageInput.files[0];
    fileChosen.textContent = file ? file.name : "No file chosen";

    // Revoke previous object URL to free memory
    if (prevObjectUrl) {
        URL.revokeObjectURL(prevObjectUrl);
        prevObjectUrl = null;
    }

    if (file) {
        prevObjectUrl = URL.createObjectURL(file);
        previewImage.src = prevObjectUrl;
        previewImage.style.display = "block";
        previewEmpty.classList.add("hidden");
        // Replay reveal animation
        previewImage.classList.remove("img-revealed");
        void previewImage.offsetWidth;
        previewImage.classList.add("img-revealed");
    } else {
        previewImage.style.display = "none";
        previewImage.src = "";
        previewEmpty.classList.remove("hidden");
    }
});

// ── Status helper ─────────────────────────────────────────────
// [ANIMATION HELPER] Replaces the native status.innerText/innerHTML calls with
// a version that also swaps state classes and replays the fade animation.
// The core upload/gallery logic below still writes to status — this helper
// is called by the new wrappers; it does NOT touch fetch or response logic.
function setStatus(type, html) {
    // Remove previous state classes
    status.classList.remove("status-uploading", "status-success", "status-error", "status-update");

    // Set content (mirrors what script.js already does)
    status.innerHTML = html;

    // Apply new state class
    if (type) status.classList.add(`status-${type}`);

    // Replay animation: remove then re-add the trigger class next frame
    requestAnimationFrame(() => {
        status.classList.add("status-update");
    });
    // Clean up animation class after it ends so it can replay again
    status.addEventListener("animationend", () => {
        status.classList.remove("status-update");
    }, { once: true });
}

// ── Toast notification helper ────────────────────────────────────
// Replaces native browser alert() with an in-page animated toast.
// type: "success" | "error" | "info"
// duration: ms before auto-dismiss (default 4000)
const TOAST_ICONS = { success: "✅", error: "❌", info: "ℹ️" };

function showToast(message, type = "info", duration = 4000) {
    // Create container lazily so no extra HTML is needed
    let container = document.getElementById("toast-container");
    if (!container) {
        container = document.createElement("div");
        container.id = "toast-container";
        document.body.appendChild(container);
    }

    const toast = document.createElement("div");
    toast.className = `toast toast--${type}`;
    toast.setAttribute("role", "alert");
    toast.setAttribute("aria-live", "assertive");

    const icon = document.createElement("span");
    icon.className = "toast__icon";
    icon.textContent = TOAST_ICONS[type] ?? TOAST_ICONS.info;

    const msg = document.createElement("span");
    msg.className = "toast__message";
    msg.textContent = message;

    const closeBtn = document.createElement("button");
    closeBtn.className = "toast__close";
    closeBtn.setAttribute("aria-label", "Dismiss");
    closeBtn.textContent = "×";
    closeBtn.addEventListener("click", () => dismiss(toast));

    toast.appendChild(icon);
    toast.appendChild(msg);
    toast.appendChild(closeBtn);
    container.appendChild(toast);

    // Auto-dismiss after duration
    const timer = setTimeout(() => dismiss(toast), duration);

    function dismiss(el) {
        clearTimeout(timer);
        el.classList.add("toast--leaving");
        el.addEventListener("animationend", () => el.remove(), { once: true });
        // Fallback removal if animation is disabled
        setTimeout(() => el.remove(), 400);
    }
}

// ── Blob-based download helper ────────────────────────────────
// [DOWNLOAD FIX] Using the `download` attribute on a cross-origin pre-signed
// S3 URL causes the browser to modify request headers, breaking the AWS
// signature (SignatureDoesNotMatch). Fetching as a blob and creating a local
// object URL sidesteps this entirely.
async function downloadImage(url, filename) {
    try {
        const res = await fetch(url);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const blob = await res.blob();
        const objectUrl = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = objectUrl;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(objectUrl);
    } catch (err) {
        console.error("Download failed:", err);
        showToast("Download failed. Try right-clicking the image and saving it.", "error");
    }
}

// ── Gallery stagger helper ─────────────────────────────────────
// [ANIMATION HELPER] After loadGallery() rebuilds innerHTML, this sets the
// CSS --i variable on each card so the stagger delay works, and adds the
// .card-animate class to trigger the entrance animation.
// The images inside are also wrapped in a div for the hover zoom overflow.
function applyGalleryAnimations() {
    const cards = gallery.querySelectorAll(".gallery-card");
    cards.forEach((card, i) => {
        card.style.setProperty("--i", i);
        // Force reflow so animation restarts even if class was already present
        card.classList.remove("card-animate");
        void card.offsetWidth; // reflow
        card.classList.add("card-animate");
    });
}

// ── Gallery loader ─────────────────────────────────────────────
// URLs are set via DOM properties (not innerHTML attribute strings) to
// prevent the browser's HTML parser from mangling the & characters in
// pre-signed S3 query strings, which would corrupt the AWS signature.
async function loadGallery() {

    const API_URL = "https://txqyd7x425.execute-api.eu-north-1.amazonaws.com";
    const response = await fetch(API_URL + "/gallery");

    const images = await response.json();

    gallery.innerHTML = "";

    images.forEach(image => {

        // Build each card via DOM API so URLs are assigned as JS properties,
        // never injected into HTML strings. The browser's HTML parser would
        // decode & → &amp; in attribute strings, corrupting the pre-signed
        // S3 query parameters and causing SignatureDoesNotMatch.
        const card = document.createElement("div");
        card.className = "gallery-card";

        const imgWrapper = document.createElement("div");
        imgWrapper.className = "gallery-card__img-wrapper";

        const img = document.createElement("img");
        img.src = image.url;          // property assignment — skips HTML parser
        img.alt = image.filename;
        img.loading = "lazy";
        imgWrapper.appendChild(img);

        const body = document.createElement("div");
        body.className = "gallery-card__body";

        const name = document.createElement("p");
        name.title = image.filename;
        name.textContent = image.filename;

        const viewBtn = document.createElement("a");
        viewBtn.href = image.url;     // property assignment — skips HTML parser
        viewBtn.target = "_blank";
        viewBtn.rel = "noopener noreferrer";
        viewBtn.className = "btn btn-secondary";
        viewBtn.title = "Open full size";
        viewBtn.innerHTML = `<span class="icon-download" aria-hidden="true">&#128065;</span> View`;

        const dlBtn = document.createElement("button");
        dlBtn.className = "btn btn-secondary";
        dlBtn.innerHTML = `<span class="icon-download" aria-hidden="true">&#8681;</span> Download`;
        dlBtn.addEventListener("click", () => downloadImage(image.url, image.filename));

        body.appendChild(name);
        body.appendChild(viewBtn);
        body.appendChild(dlBtn);
        card.appendChild(imgWrapper);
        card.appendChild(body);
        gallery.appendChild(card);

    });

    // [ANIMATION HELPER] Apply stagger entrance animation after render
    applyGalleryAnimations();
}

// ── Post-upload gallery poller ───────────────────────────────────
// After a successful S3 PUT the process Lambda runs asynchronously, so
// the processed image won't exist immediately. This function polls the
// gallery API every INTERVAL ms for up to MAX_WAIT ms and stops as soon
// as the gallery count increases (new image appeared) or the timeout hits.
async function pollGalleryUntilNew(previousCount) {
    const INTERVAL = 3000;  // poll every 3 seconds
    const MAX_WAIT = 30000; // give up after 30 seconds
    const started  = Date.now();

    async function poll() {
        try {
            const API_URL = "https://txqyd7x425.execute-api.eu-north-1.amazonaws.com";
            const res     = await fetch(API_URL + "/gallery");
            const images  = await res.json();

            if (images.length > previousCount) {
                // New image detected — rebuild gallery and stop polling
                await loadGallery();
                showToast("🏎️ Image processed and added to gallery!", "success");
                return;
            }
        } catch (e) {
            console.warn("Gallery poll error:", e);
        }

        if (Date.now() - started < MAX_WAIT) {
            setTimeout(poll, INTERVAL);
        } else {
            // Timed out — do a final reload and let the user know
            await loadGallery();
            showToast("Processing is taking longer than usual. Gallery refreshed.", "info");
        }
    }

    // Small initial delay so the Lambda has time to start
    setTimeout(poll, INTERVAL);
}

// ── Upload button click handler ───────────────────────────────
// !! The core fetch/response/show-hide logic below is UNCHANGED !!
// Only the status text calls have been updated to use setStatus(),
// and loading state class is toggled on uploadBtn for the spinner.
uploadBtn.addEventListener("click", async () => {

    if (imageInput.files.length === 0) {

        // [MODIFIED] was: status.innerText = "Please select an image."
        setStatus("error", "Please select an image.");

        return;

    }

    const file = imageInput.files[0];

    const formData = new FormData();
    formData.append("image", file);
    formData.append("processType", processType.value);

    try {

        // [ANIMATION HELPER] Enter loading state — disables button, shows spinner
        uploadBtn.disabled = true;
        uploadBtn.classList.add("btn-loading");

        // [MODIFIED] was: status.innerText = "Uploading..."
        setStatus("uploading", "Uploading…");

        // POST to Lambda to get a presigned URL; send the file's MIME type so
        // the Lambda signs the URL for the exact Content-Type we'll PUT with.
        const API_URL = "https://txqyd7x425.execute-api.eu-north-1.amazonaws.com";
        const response = await fetch(API_URL + "/upload", {
    method: "POST",
    headers: {
        "Content-Type": "application/json"
    },
    body: JSON.stringify({
        contentType: file.type,
        processType: processType.value
    })
});

const data = await response.json();

const uploadUrl = data.uploadUrl;

const fileName = data.fileName;

const uploadResponse = await fetch(uploadUrl, {
    method:"PUT",
    headers:{
        "Content-Type":file.type
    },
    body:file
});
if(uploadResponse.ok){

    showToast("Image uploaded successfully! Processing in the background…", "success");

    // Get current gallery count, then poll until the new processed image appears
    const currentCount = gallery.querySelectorAll(".gallery-card").length;
    pollGalleryUntilNew(currentCount);

}
else{

    showToast("Upload failed. Please try again.", "error");

}

    } catch (error) {

        console.error(error);

        // [MODIFIED] was: status.innerText = "Upload Failed"
        setStatus("error", "Upload Failed. Please check your connection and try again.");

    } finally {

        // [ANIMATION HELPER] Always exit loading state
        uploadBtn.disabled = false;
        uploadBtn.classList.remove("btn-loading");

    }

});

// ── Initial gallery load on page open ─────────────────────────
loadGallery();