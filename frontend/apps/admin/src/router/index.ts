import type { Component } from 'vue'
import NProgress from 'nprogress'
import { createRouter, createWebHashHistory, type RouteRecordRaw } from 'vue-router'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { useUserStore } from '@/stores/user'

NProgress.configure({ showSpinner: false })

export interface AdminMenuItem {
  path: string
  title: string
  icon: AdminMenuIcon
  children?: AdminMenuItem[]
}

export type AdminMenuIcon = 'Collection' | 'DataLine' | 'EditPen' | 'Reading' | 'Tickets'
export type AdminMenuIconMap = Record<AdminMenuIcon, Component>

export const adminMenus: AdminMenuItem[] = [
  { path: '/dashboard', title: '主页', icon: 'DataLine' },
  {
    path: '/education',
    title: '教育管理',
    icon: 'Reading',
    children: [{ path: '/education/subject/list', title: '学科列表', icon: 'Collection' }]
  },
  {
    path: '/exam',
    title: '卷题管理',
    icon: 'Tickets',
    children: [{ path: '/exam/question/list', title: '题目列表', icon: 'EditPen' }]
  }
]

const routes: RouteRecordRaw[] = [
  {
    path: '/login',
    name: 'Login',
    component: () => import('@/views/login/LoginView.vue'),
    meta: { title: '登录', public: true }
  },
  {
    path: '/',
    component: AdminLayout,
    redirect: '/dashboard',
    children: [
      {
        path: 'dashboard',
        name: 'Dashboard',
        component: () => import('@/views/dashboard/DashboardView.vue'),
        meta: { title: '主页' }
      },
      {
        path: 'education/subject/list',
        name: 'EducationSubjectList',
        component: () => import('@/views/education/SubjectListView.vue'),
        meta: { title: '学科列表' }
      },
      {
        path: 'exam/question/list',
        name: 'ExamQuestionList',
        component: () => import('@/views/question/QuestionListView.vue'),
        meta: { title: '题目列表' }
      },
      {
        path: 'exam/question/edit',
        name: 'ExamQuestionEdit',
        component: () => import('@/views/question/QuestionEditView.vue'),
        meta: { title: '题目编辑' }
      }
    ]
  },
  {
    path: '/:pathMatch(.*)*',
    name: 'NotFound',
    component: () => import('@/views/system/NotFoundView.vue'),
    meta: { title: '页面不存在', public: true }
  }
]

export const router = createRouter({
  history: createWebHashHistory(),
  routes
})

router.beforeEach(async (to) => {
  NProgress.start()
  document.title = typeof to.meta.title === 'string' ? `${to.meta.title} - 学之思管理系统` : '学之思管理系统'

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
