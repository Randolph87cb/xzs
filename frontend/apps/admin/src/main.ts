import { createApp } from 'vue'
import { ElLoading, ElMessage } from 'element-plus'
import 'element-plus/es/components/loading/style/css'
import 'element-plus/es/components/message/style/css'
import 'element-plus/es/components/message-box/style/css'
import { createPinia } from 'pinia'
import { configureApiClient } from '@xzs/api-client'
import App from './App.vue'
import { router } from './router'
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
app.directive('loading', ElLoading.directive)
app.mount('#app')
