import NProgress from 'nprogress'
import { createRouter, createWebHashHistory } from 'vue-router'
import ShellLayout from '@/layouts/ShellLayout.vue'
import { useUserStore } from '@/stores/user'

NProgress.configure({ showSpinner: false })

export const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    {
      path: '/login',
      name: 'Login',
      component: () => import('@/views/login/LoginView.vue'),
      meta: { title: '登录', bodyBackground: '#fbfbfb', public: true }
    },
    {
      path: '/',
      component: ShellLayout,
      redirect: '/index',
      children: [
        {
          path: 'index',
          name: 'Dashboard',
          component: () => import('@/views/dashboard/DashboardView.vue'),
          meta: { title: '首页' }
        },
        {
          path: 'paper/index',
          name: 'PaperList',
          component: () => import('@/views/paper/PaperListView.vue'),
          meta: { title: '试卷中心' }
        },
        {
          path: 'record/index',
          name: 'RecordList',
          component: () => import('@/views/record/RecordListView.vue'),
          meta: { title: '考试记录' }
        },
        {
          path: 'question/index',
          name: 'QuestionError',
          component: () => import('@/views/question/QuestionErrorView.vue'),
          meta: { title: '错题本' }
        },
        {
          path: 'training/index',
          name: 'Training',
          component: () => import('@/views/training/TrainingView.vue'),
          meta: { title: '智能训练' }
        }
      ]
    },
    {
      path: '/do',
      name: 'ExamDo',
      component: () => import('@/views/exam/ExamDoView.vue'),
      meta: { title: '试卷答题' }
    },
    {
      path: '/read',
      name: 'ExamRead',
      component: () => import('@/views/exam/ExamReadView.vue'),
      meta: { title: '试卷查看' }
    },
    {
      path: '/:pathMatch(.*)*',
      name: 'NotFound',
      component: () => import('@/views/system/NotFoundView.vue'),
      meta: { title: '页面不存在', public: true }
    }
  ]
})

router.beforeEach(async (to) => {
  NProgress.start()
  document.title = typeof to.meta.title === 'string' ? to.meta.title : '\u200E'

  if (typeof to.meta.bodyBackground === 'string') {
    document.body.style.background = to.meta.bodyBackground
  } else {
    document.body.removeAttribute('style')
  }

  window._hmt?.push(['_trackPageview', '/#' + to.fullPath])

  const userStore = useUserStore()

  if (to.meta.public) {
    return
  }

  try {
    if (!userStore.hasCheckedSession) {
      await userStore.initUserInfo()
    }

    if (userStore.isAuthenticated) {
      return
    }
  } catch {
    userStore.clear()
  }

  return {
    path: '/login',
    query: { redirect: to.fullPath }
  }
})

router.afterEach(() => {
  NProgress.done()
})
