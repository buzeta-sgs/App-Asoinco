// ASOINCO · Función de Supabase "enviar-correo"
// Cobranza sale directo por Gmail (finanzas.asoinco@gmail.com); carta/contrato salen por Brevo (asistente@asoinco.cl).
// Las claves quedan guardadas en Supabase (Secrets), nunca en la página.
// Solo funciona para usuarios que iniciaron sesión en la app.
//
// Secrets necesarios (Supabase → Edge Functions → Secrets):
//   BREVO_API_KEY      = la clave API de Brevo (empieza con xkeysib-)
//   GMAIL_APP_PASSWORD = contraseña de aplicación de Google de finanzas.asoinco@gmail.com (16 letras)
//                        Si no está, la cobranza sigue saliendo por Brevo como antes.
// Los remitentes de Brevo están en REMITENTES, más abajo.

import nodemailer from 'npm:nodemailer@6.9.16';

const GMAIL_USER = 'finanzas.asoinco@gmail.com';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405);

  try {
    // 1) Solo usuarios con sesión iniciada en la app
    const token = (req.headers.get('Authorization') ?? '').replace('Bearer ', '');
    const who = await fetch(`${Deno.env.get('SUPABASE_URL')}/auth/v1/user`, {
      headers: { apikey: Deno.env.get('SUPABASE_ANON_KEY') ?? '', Authorization: `Bearer ${token}` },
    });
    if (!who.ok) return json({ error: 'No autorizado: inicia sesión de nuevo en la app.' }, 401);

    // 2) Datos del correo
    const { to, subject, html, attachments, remitente } = await req.json();
    // Remitente según el tipo de correo: carta/contrato = asistente; cobranza = correo de cobranza
    const REMITENTES: Record<string, { from: string; reply: string; replyName: string }> = {
      asistente: { from: 'asistente@asoinco.cl', reply: 'asistente@asoinco.cl', replyName: 'ASOINCO' },
      cobranza: { from: 'finanzas.asoinco@gmail.com', reply: 'finanzas.asoinco@gmail.com', replyName: 'Finanzas ASOINCO' },
    };
    const rem = REMITENTES[remitente] ?? REMITENTES.cobranza;
    const recipients = String(to ?? '').split(/[;,]/).map((e) => e.trim()).filter((e) => /^\S+@\S+\.\S+$/.test(e));
    if (recipients.length === 0 || recipients.length > 5) return json({ error: 'Destinatario inválido' }, 400);
    if (!subject || !html) return json({ error: 'Falta asunto o contenido' }, 400);
    const files = Array.isArray(attachments) ? attachments.slice(0, 3) : [];
    const totalSize = files.reduce((t: number, f: { content?: string }) => t + (f.content?.length ?? 0), 0);
    if (totalSize > 4_000_000) return json({ error: 'Adjuntos demasiado pesados' }, 400);

    // 3a) Cobranza: directo por el Gmail de finanzas (así el remitente se ve real, sin "brevosend.com")
    const gmailPass = Deno.env.get('GMAIL_APP_PASSWORD');
    if (remitente !== 'asistente' && gmailPass) {
      const transporter = nodemailer.createTransport({
        host: 'smtp.gmail.com',
        port: 465,
        secure: true,
        auth: { user: GMAIL_USER, pass: gmailPass.replace(/\s+/g, '') },
      });
      const info = await transporter.sendMail({
        from: `"ASOINCO" <${GMAIL_USER}>`,
        replyTo: `"Finanzas ASOINCO" <${GMAIL_USER}>`,
        to: recipients.join(', '),
        subject,
        html,
        attachments: files.map((f: { name: string; content: string }) => ({ filename: f.name, content: f.content, encoding: 'base64' })),
      });
      return json({ ok: true, id: info.messageId });
    }

    // 3b) Carta/contrato (asistente@asoinco.cl): por Brevo
    const brevo = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': Deno.env.get('BREVO_API_KEY') ?? '', 'Content-Type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({
        sender: { name: 'ASOINCO', email: rem.from },
        replyTo: { email: rem.reply, name: rem.replyName },
        to: recipients.map((email) => ({ email })),
        subject,
        htmlContent: html,
        attachment: files.length ? files.map((f: { name: string; content: string }) => ({ name: f.name, content: f.content })) : undefined,
      }),
    });
    const out = await brevo.json().catch(() => ({}));
    if (!brevo.ok) return json({ error: out.message || `Brevo respondió ${brevo.status}` }, 502);
    return json({ ok: true, id: out.messageId });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
