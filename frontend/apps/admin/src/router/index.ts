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
    path: '/user',
    title: '用户管理',
    icon: 'Collection',
    children: [
      { path: '/user/student/list', title: '学生列表', icon: 'Collection' },
      { path: '/user/admin/list', title: '管理员列表', icon: 'Collection' }
    ]
  },
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
    children: [
      { path: '/exam/paper/list', title: '试卷列表', icon: 'Tickets' },
      { path: '/exam/question/list', title: '题目列表', icon: 'EditPen' },
      { path: '/exam/question/review', title: '题目质量审核', icon: 'EditPen' },
      { path: '/exam/question/correction', title: '改错审核', icon: 'EditPen' },
      { path: '/exam/smartTraining/config', title: '智能训练配置', icon: 'DataLine' }
    ]
  },
  {
    path: '/task',
    title: '任务管理',
    icon: 'EditPen',
    children: [{ path: '/task/list', title: '任务列表', icon: 'EditPen' }]
  },
  {
    path: '/answer',
    title: '成绩管理',
    icon: 'Tickets',
    children: [{ path: '/answer/list', title: '答卷列表', icon: 'Tickets' }]
  },
  {
    path: '/message',
    title: '消息中心',
    icon: 'EditPen',
    children: [
      { path: '/message/list', title: '消息列表', icon: 'EditPen' },
      { path: '/message/send', title: '消息发送', icon: 'EditPen' }
    ]
  },
  {
    path: '/log',
    title: '日志中心',
    icon: 'DataLine',
    children: [{ path: '/log/user/list', title: '用户日志', icon: 'DataLine' }]
  },
  {
    path: '/profile/index',
    title: '个人简介',
    icon: 'Collection'
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
        path: 'education/subject/edit',
        name: 'EducationSubjectEdit',
        component: () => import('@/views/education/SubjectEditView.vue'),
        meta: { title: '学科编辑' }
      },
      {
        path: 'user/student/list',
        name: 'UserStudentList',
        component: () => import('@/views/user/UserListView.vue'),
        props: { role: 1 },
        meta: { title: '学生列表' }
      },
      {
        path: 'user/student/edit',
        name: 'UserStudentEdit',
        component: () => import('@/views/user/UserEditView.vue'),
        props: { role: 1 },
        meta: { title: '学生编辑' }
      },
      {
        path: 'user/admin/list',
        name: 'UserAdminList',
        component: () => import('@/views/user/UserListView.vue'),
        props: { role: 3 },
        meta: { title: '管理员列表' }
      },
      {
        path: 'user/admin/edit',
        name: 'UserAdminEdit',
        component: () => import('@/views/user/UserEditView.vue'),
        props: { role: 3 },
        meta: { title: '管理员编辑' }
      },
      {
        path: 'exam/paper/list',
        name: 'ExamPaperList',
        component: () => import('@/views/paper/PaperListView.vue'),
        meta: { title: '试卷列表' }
      },
      {
        path: 'exam/paper/edit',
        name: 'ExamPaperEdit',
        component: () => import('@/views/paper/PaperEditView.vue'),
        meta: { title: '试卷编辑' }
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
      },
      {
        path: 'exam/question/edit/:legacyType',
        redirect: (to) => ({ path: '/exam/question/edit', query: to.query })
      },
      {
        path: 'exam/question/review',
        name: 'ExamQuestionReview',
        component: () => import('@/views/question/QuestionReviewView.vue'),
        meta: { title: '题目质量审核' }
      },
      {
        path: 'exam/question/correction',
        name: 'ExamQuestionCorrectionReview',
        component: () => import('@/views/question/QuestionCorrectionReviewView.vue'),
        meta: { title: '改错审核' }
      },
      {
        path: 'exam/smartTraining/config',
        name: 'ExamSmartTrainingConfig',
        component: () => import('@/views/smartTraining/SmartTrainingConfigView.vue'),
        meta: { title: '智能训练配置' }
      },
      {
        path: 'task/list',
        name: 'TaskList',
        component: () => import('@/views/task/TaskListView.vue'),
        meta: { title: '任务列表' }
      },
      {
        path: 'task/edit',
        name: 'TaskEdit',
        component: () => import('@/views/task/TaskEditView.vue'),
        meta: { title: '任务创建' }
      },
      {
        path: 'answer/list',
        name: 'AnswerList',
        component: () => import('@/views/answer/AnswerListView.vue'),
        meta: { title: '答卷列表' }
      },
      {
        path: 'message/list',
        name: 'MessageList',
        component: () => import('@/views/message/MessageListView.vue'),
        meta: { title: '消息列表' }
      },
      {
        path: 'message/send',
        name: 'MessageSend',
        component: () => import('@/views/message/MessageSendView.vue'),
        meta: { title: '消息发送' }
      },
      {
        path: 'log/user/list',
        name: 'UserLogList',
        component: () => import('@/views/log/UserLogListView.vue'),
        meta: { title: '用户日志' }
      },
      {
        path: 'profile/index',
        name: 'Profile',
        component: () => import('@/views/profile/ProfileView.vue'),
        meta: { title: '个人简介' }
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
