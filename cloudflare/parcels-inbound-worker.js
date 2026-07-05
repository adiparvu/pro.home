const INBOUND_URL = "https://kwcanenheihuylaymwsl.supabase.co/functions/v1/email-inbound?secret=92c69de9a5aa9f82e41aeaa0d29c43171dd87d68c18ae4bc";
const MY_EMAIL = "adrianparvu0803@gmail.com";

export default {
  async email(message) {
    // Let Gmail's forwarding-confirmation email reach you so you can approve it.
    if ((message.from || "").includes("forwarding-noreply@google.com")) {
      try { await message.forward(MY_EMAIL); } catch (_) {}
      return;
    }
    const raw = await new Response(message.raw).text();
    await fetch(INBOUND_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ to: message.to, from: message.from, raw }),
    });
  }
};
