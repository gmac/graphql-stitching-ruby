const fs = require('fs');
const path = require('path');
const { buildSchema, printSchema } = require('graphql');
const { filterSchema, pruneSchema } = require('@graphql-tools/utils');

const filepath = path.join(__dirname, 'admin_2023_01.graphql');
const schema = buildSchema(fs.readFileSync(filepath, 'utf8'));
const filteredSchema = pruneSchema(filterSchema({
  schema: schema,
  rootFieldFilter: (type, fieldName) => fieldName === 'product',
}));

console.log(printSchema(filteredSchema));
