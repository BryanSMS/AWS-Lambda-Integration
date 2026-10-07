const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { randomUUID } = require("crypto");

const s3 = new S3Client({});

const MAX_BYTES = 4 * 1024 * 1024;
const ALLOWED = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/gif": "gif",
    "image/webp": "webp",
};
const respond = (statusCode, body) => ({
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
});

exports.handler = async (event) => {
  try {
    const contentType = (event.headers["content-type"] || "").split(";")[0].trim();
    const ext = ALLOWED[contentType];
    if (!ext) {
        return respond(415, { error: "Tipo no permitido. Usa jpg, png, gif o webp." });
    }
    if (!event.body) {
        return respond(400, { error: "Cuerpo vacío." });
    }
    const buffer = Buffer.from(event.body, event.isBase64Encoded ? "base64" : "utf8");

    if (buffer.length > MAX_BYTES) {
        return respond(413, { error: "La imagen supera los 4 MB." });
    }

    const key = `${process.env.UPLOAD_PREFIX}${randomUUID()}.${ext}`;
    await s3.send(
        new PutObjectCommand({
            Bucket: process.env.S3_BUCKET,
            Key: key,
            Body: buffer,
            ContentType: contentType,
      })
    );
    return respond(201, { message: "Imagen recibida", key });
  } catch (err) {
    console.error("Error en upload:", err);
    return respond(500, { error: "Error interno." });
  }
};
