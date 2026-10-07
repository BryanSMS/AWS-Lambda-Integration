const { S3Client, GetObjectCommand, PutObjectCommand } = require("@aws-sdk/client-s3");
const sharp = require("sharp");
const path = require("path");

const s3 = new S3Client({});
const SIZE = 40;

const circleMask = Buffer.from(
    `<svg width="${SIZE}" height="${SIZE}"><circle cx="${SIZE / 2}" cy="${SIZE / 2}" r="${SIZE / 2}" fill="#fff"/></svg>`
);

async function cropImage(key) {
    const original = await s3.send(
        new GetObjectCommand({ Bucket: process.env.S3_BUCKET, Key: key })
    );
    const input = Buffer.from(await original.Body.transformToByteArray());
    const output = await sharp(input)
    .resize(SIZE, SIZE, { fit: "cover" })
    .composite([{ input: circleMask, blend: "dest-in" }])
    .png()
    .toBuffer();


    const name = path.parse(key).name;
    const outKey = `${process.env.PROCESSED_PREFIX}${name}_circular.png`;

    await s3.send(
        new PutObjectCommand({
        Bucket: process.env.S3_BUCKET,
        Key: outKey,
        Body: output,
        ContentType: "image/png",
        })
    );
    console.log(`OK: ${key} -> ${outKey}`);
}

async function processMessage(message) {
    const body = JSON.parse(message.body);
    if (body.Event === "s3:TestEvent" || !body.Records) {
        console.log("Mensaje sin imágenes, se omite.");
        return; 
    }

    for (const record of body.Records) {
        const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));
        if (!key.startsWith(process.env.UPLOAD_PREFIX)) continue;
        await cropImage(key);
    }
}
exports.handler = async (event) => {
    const batchItemFailures = [];
    for (const message of event.Records) {
        try {
        await processMessage(message);
        } catch (err) {
        console.error(`Falló el mensaje ${message.messageId}:`, err);
        batchItemFailures.push({ itemIdentifier: message.messageId });
        }
  }
  return { batchItemFailures };
};