export {}

declare global {
  interface Window {
    _hmt?: Array<unknown[]>
  }
}

declare module 'vue-router' {
  interface RouteMeta {
    title?: string
    bodyBackground?: string
    public?: boolean
  }
}
