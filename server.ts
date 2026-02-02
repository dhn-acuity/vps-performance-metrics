import app from './index'
import { serve } from '@hono/node-server'

serve({
  fetch: app.fetch,
  port: 3000,
})

console.log('Hono metrics server running on port 3000')
