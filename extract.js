const admin = require("firebase-admin");
const fs = require("fs");

admin.initializeApp({
  credential: admin.credential.cert(require("./assets/service_account.json")),
});

const db = admin.firestore();

async function extractSchema() {
  const schema = {};
  const collections = await db.listCollections();

  for (const col of collections) {
    const snapshot = await col.limit(1).get();
    if (!snapshot.empty) {
      schema[col.id] = Object.fromEntries(
        Object.entries(snapshot.docs[0].data()).map(([k, v]) => [k, typeof v])
      );
    }
  }

  fs.writeFileSync("firestore-schema.json", JSON.stringify(schema, null, 2));
  console.log("Done!");
}

extractSchema();