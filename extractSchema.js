const admin = require('firebase-admin');
const serviceAccount = require('./service_account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

function inferType(value) {
  if (value === null) return 'null';
  if (value instanceof admin.firestore.Timestamp) return 'timestamp';
  if (value instanceof admin.firestore.GeoPoint) return 'geopoint';
  if (value instanceof admin.firestore.DocumentReference) return 'reference';
  if (Array.isArray(value)) {
    const itemType = value.length > 0 ? inferType(value[0]) : 'unknown';
    return `array<${itemType}>`;
  }
  if (typeof value === 'object') {
    const nested = {};
    for (const [k, v] of Object.entries(value)) {
      nested[k] = inferType(v);
    }
    return nested;
  }
  return typeof value;
}

async function extractCollectionSchema(collectionRef, sampleSize = 5) {
  const snapshot = await collectionRef.limit(sampleSize).get();
  const mergedSchema = {};

  for (const doc of snapshot.docs) {
    const data = doc.data();
    for (const [field, value] of Object.entries(data)) {
      if (!(field in mergedSchema)) {
        mergedSchema[field] = inferType(value);
      }
    }

    const subcollections = await doc.ref.listCollections();
    for (const sub of subcollections) {
      const subSchema = await extractCollectionSchema(sub, sampleSize);
      mergedSchema[`__subcollection__${sub.id}`] = subSchema;
    }
  }

  return mergedSchema;
}

async function extractFullSchema() {
  const schema = {};
  const rootCollections = await db.listCollections();

  for (const col of rootCollections) {
    console.log(`📂 Scanning collection: ${col.id}`);
    schema[col.id] = await extractCollectionSchema(col);
  }

  return schema;
}

extractFullSchema()
  .then(schema => {
    console.log('\n✅ Firestore Schema:\n');
    console.log(JSON.stringify(schema, null, 2));
    const fs = require('fs');
    fs.writeFileSync('firestore-schema.json', JSON.stringify(schema, null, 2));
    console.log('\n💾 Saved to firestore-schema.json');
  })
  .catch(console.error)
  .finally(() => process.exit());