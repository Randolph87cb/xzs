import { createApp } from 'vue'
import ElementPlus from 'element-plus'
import { ElMessage } from 'element-plus'
import { createPinia } from 'pinia'
import { configureApiClient } from '@xzs/api-client'
import App from './App.vue'
import { router } from './router'
import 'element-plus/dist/index.css'
import 'nprogress/nprogress.css'
import './styles/index.scss'

const app = createApp(App)
const pinia = createPinia()

configureApiClient({
  onUnauthorized: () => {
    router.push({ path: '/login' })
  },
  onError: (message) => {
    ElMessage.error(message)
  }
})

app.use(pinia)
app.use(router)
app.use(ElementPlus)
app.mount('#app')
