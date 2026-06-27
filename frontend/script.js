const uploadBtn = document.getElementById("uploadBtn");
const imageInput = document.getElementById("imageInput");
const status = document.getElementById("status");
const processType = document.getElementById("processType");
const processedImage = document.getElementById("processedImage");
uploadBtn.addEventListener("click", async () => {

    if (imageInput.files.length === 0) {

        status.innerText = "Please select an image.";

        return;

    }

    const file = imageInput.files[0];

    const formData = new FormData();
    formData.append("image", file);
    formData.append("processType", processType.value);

    try {

        status.innerText = "Uploading...";

        const response = await fetch(
            "http://127.0.0.1:5000/upload",
            {
                method: "POST",
                body: formData
            }
        );

        const data = await response.json();

        status.innerHTML = `
<h3>${data.message}</h3>

<p><strong>Original:</strong> ${data.original}</p>

<p><strong>Processed:</strong> ${data.processed}</p>
`;

        processedImage.src = data.imageUrl + "?t=" + new Date().getTime();

        processedImage.style.display = "block";

    } catch (error) {

        console.error(error);

        status.innerText = "Upload Failed";

    }

});