const express = require('express');
const { Pool } = require('pg');
const client = require('prom-client');

const app = express();
app.use(express.json());

// 1. Configure the PostgreSQL Connection Pool
const pool = new Pool({
  host: process.env.DB_HOST || 'postgres-service',
  user: process.env.DB_USER || 'devopsadmin',
  password: process.env.DB_PASSWORD || 'supersecurecloudpassword123',
  database: process.env.DB_NAME || 'app_production',
  port: 5432,
});

// 2. Initialize Prometheus System Metrics Tracking
const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics({ register: client.register });

// 3. Define the Custom Counter Metric for CRUD Operations
const inventoryOperationsCounter = new client.Counter({
  name: 'inventory_operations_total',
  help: 'Total number of items processed by the CRUD engine',
  labelNames: ['action', 'status'] // Allows sorting metrics by action type and success state
});

// 4. Asynchronous Database Initialization
const initDb = async () => {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS inventory (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL
    );
  `);
};

initDb()
  .then(() => console.log('Database initialized and schema verified.'))
  .catch((err) => console.error('Database initialization failed:', err));

// 5. API Routes Instrumented with Prometheus Counters

// GET: Fetch all items
app.get('/items', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM inventory ORDER BY id DESC');
    res.status(200).json(result.rows);
  } catch (error) {
    console.error(error.message);
    res.status(500).send(error.message);
  }
});

// POST: Add a new item
app.post('/items', async (req, res) => {
  const { name } = req.body;
  try {
    const result = await pool.query('INSERT INTO inventory (name) VALUES ($1) RETURNING *', [name]);
    
    // Increment Prometheus counter on SUCCESS
    inventoryOperationsCounter.inc({ action: 'add', status: 'success' });
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error(error.message);
    
    // Increment Prometheus counter on FAILURE
    inventoryOperationsCounter.inc({ action: 'add', status: 'failed' });
    res.status(500).send(error.message);
  }
});

// DELETE: Remove an item
app.delete('/items/:id', async (req, res) => {
  const { id } = req.params;
  try {
    await pool.query('DELETE FROM inventory WHERE id = $1', [id]);
    
    // Increment Prometheus counter on SUCCESS ///
    inventoryOperationsCounter.inc({ action: 'delete', status: 'success' });
    res.status(200).send({ message: 'Item deleted' });
  } catch (error) {
    console.error(error.message);
    
    // Increment Prometheus counter on FAILURE
    inventoryOperationsCounter.inc({ action: 'delete', status: 'failed' });
    res.status(500).send(error.message);
  }
});

// 6. Expose the /metrics scrapable endpoint for Prometheus
app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', client.register.contentType);
    res.end(await client.register.metrics());
  } catch (err) {
    res.status(500).end(err);
  }
});

app.listen(3000, () => {
  console.log('Backend running on port 3000');
});