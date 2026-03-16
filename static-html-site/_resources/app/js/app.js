const button = document.getElementById("cta");
const message = document.getElementById("message");

if (button && message) {
  button.addEventListener("click", () => {
    message.textContent = "Hello from your PartRocks static site!";
  });
}
