import NProgress from 'nprogress'
import { createRouter, createWebHashHistory } from 'vue-router'
import LoginView from '@/views/login/LoginView.vue'
import DashboardView from '@/views/dashboard/DashboardView.vue'
import ShellLayout from '@/layouts/ShellLayout.vue'
import NotFoundView from '@/views/system/NotFoundView.vue'

NProgress.configure({ showSpinner: false })

export const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    {
      path: '/login',
      name: 'Login',
      component: LoginView,
      meta: { title: '登录', bodyBackground: '#fbfbfb' }
    },
    {
      path: '/',
      component: ShellLayout,
      redirect: '/index',
      children: [
        {
          path: 'index',
          name: 'Dashboard',
          component: DashboardView,
          meta: { title: '首页' }
        }
      ]
    },
    {
      path: '/:pathMatch(.*)*',
      name: 'NotFound',
      component: NotFoundView,
      meta: { title: '页面不存在' }
    }
  ]
})

router.beforeEach((to) => {
  NProgress.start()
  document.title = typeof to.meta.title === 'string' ? to.meta.title : '\u200E'

  if (typeof to.meta.bodyBackground === 'string') {
    document.body.style.background = to.meta.bodyBackground
  } else {
    document.body.removeAttribute('style')
  }

  window._hmt?.push(['_trackPageview', '/#' + to.fullPath])
})

router.afterEach(() => {
  NProgress.done()
})
