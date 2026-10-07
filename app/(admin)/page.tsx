import { redirect } from 'next/navigation'

/** Sentral Simple opens on Customers (the full interface's overview is at /overview). */
export default function Home() {
  redirect('/customers')
}
