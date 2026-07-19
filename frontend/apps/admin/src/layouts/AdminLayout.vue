<template>
  <el-container class="admin-layout">
    <el-aside class="admin-layout__aside" :class="{ 'is-collapsed': isAsideCollapsed }" :width="asideWidth">
      <div class="admin-layout__brand">
        <img class="admin-layout__mark" :src="appIconUrl" alt="" />
        <div v-show="!isAsideCollapsed" class="admin-layout__brand-text">
          <strong>信息学客观题一本通</strong>
          <span>信息学智能组卷</span>
        </div>
      </div>
      <el-menu
        router
        :collapse="isAsideCollapsed"
        :collapse-transition="false"
        :default-active="route.path"
        class="admin-layout__menu"
      >
        <template v-for="item in visibleAdminMenus" :key="item.path">
          <el-sub-menu v-if="item.children?.length" :index="item.path">
            <template #title>
              <component :is="iconMap[item.icon]" class="admin-layout__menu-icon" />
              <span>{{ item.title }}</span>
            </template>
            <el-menu-item v-for="child in item.children" :key="child.path" :index="child.path">
              <component :is="iconMap[child.icon]" class="admin-layout__menu-icon" />
              <span>{{ child.title }}</span>
            </el-menu-item>
          </el-sub-menu>
          <el-menu-item v-else :index="item.path">
            <component :is="iconMap[item.icon]" class="admin-layout__menu-icon" />
            <span>{{ item.title }}</span>
          </el-menu-item>
        </template>
      </el-menu>
    </el-aside>

    <el-container>
      <el-header class="admin-layout__header">
        <div class="admin-layout__header-left">
          <el-tooltip :content="isAsideCollapsed ? '展开菜单' : '收起菜单'" placement="bottom">
            <el-button
              class="admin-layout__collapse-button"
              :icon="isAsideCollapsed ? Expand : Fold"
              circle
              text
              :aria-label="isAsideCollapsed ? '展开菜单' : '收起菜单'"
              @click="toggleAside"
            />
          </el-tooltip>
          <div class="admin-layout__title">管理后台</div>
          <nav class="admin-layout__tabs" aria-label="后台视图">
            <RouterLink
              v-for="tab in visibleHeaderTabs"
              :key="tab.path"
              class="admin-layout__tab"
              :class="{ 'is-active': tab.isActive(route.path) }"
              :to="tab.path"
            >
              {{ tab.title }}
            </RouterLink>
          </nav>
        </div>
        <div class="admin-layout__user">
          <el-button :icon="Search" circle text aria-label="搜索" />
          <el-button :icon="Bell" circle text aria-label="通知" />
          <el-button :icon="QuestionFilled" circle text aria-label="帮助" />
          <el-avatar :size="32" :src="userStore.userInfo?.imagePath">{{ userInitial }}</el-avatar>
          <span>{{ userStore.userInfo?.userName ?? userStore.userName }}</span>
          <el-button text @click="handleLogout">退出</el-button>
        </div>
      </el-header>
      <el-main class="admin-layout__main">
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  Bell,
  Collection,
  DataLine,
  EditPen,
  Expand,
  Fold,
  QuestionFilled,
  Reading,
  Search,
  Tickets
} from '@element-plus/icons-vue'
import { useRoute, useRouter } from 'vue-router'
import { adminMenus, type AdminMenuIconMap, type AdminMenuItem } from '@/router'
import { useUserStore } from '@/stores/user'

const iconMap: AdminMenuIconMap = {
  Collection,
  DataLine,
  EditPen,
  Reading,
  Tickets
}
const route = useRoute()
const router = useRouter()
const userStore = useUserStore()
const appIconUrl = `${import.meta.env.BASE_URL}app-icon.svg`
const asideStorageKey = 'xzs-admin-aside-collapsed'
const isAsideCollapsed = ref(readAsideCollapsed())
const asideWidth = computed(() => (isAsideCollapsed.value ? '64px' : '232px'))
const userInitial = computed(() => (userStore.userInfo?.userName ?? userStore.userName ?? 'A').slice(0, 1).toUpperCase())
const adminHeaderTabs = [
  { title: '数据看板', path: '/dashboard', isActive: (path: string) => path === '/dashboard' },
  { title: '考试管理', path: '/exam/paper/list', isActive: (path: string) => path.startsWith('/exam') },
  { title: '用户中心', path: '/user/student/list', isActive: (path: string) => path.startsWith('/user') }
]
const teacherHeaderTabs = [
  { title: '班级管理', path: '/class/list', isActive: (path: string) => path.startsWith('/class') },
  { title: '学生管理', path: '/user/student/list', isActive: (path: string) => path.startsWith('/user/student') },
  { title: '任务管理', path: '/task/list', isActive: (path: string) => path.startsWith('/task') },
  { title: '答卷列表', path: '/answer/list', isActive: (path: string) => path.startsWith('/answer') },
  { title: '改错审核', path: '/exam/question/correction', isActive: (path: string) => path === '/exam/question/correction' }
]
const visibleHeaderTabs = computed(() => (userStore.userInfo?.role === 2 ? teacherHeaderTabs : adminHeaderTabs))
const teacherMenuPaths = new Set(['/class/list', '/user/student/list', '/task/list', '/answer/list', '/exam/question/correction', '/profile/index'])
const visibleAdminMenus = computed(() => {
  if (userStore.userInfo?.role !== 2) {
    return adminMenus
  }
  return adminMenus
    .map((item): AdminMenuItem | null => {
      if (!item.children?.length) {
        return teacherMenuPaths.has(item.path) ? item : null
      }
      const children = item.children.filter((child) => teacherMenuPaths.has(child.path))
      return children.length ? { ...item, children } : null
    })
    .filter((item): item is AdminMenuItem => Boolean(item))
})

function readAsideCollapsed() {
  return window.localStorage.getItem(asideStorageKey) === '1'
}

function toggleAside() {
  isAsideCollapsed.value = !isAsideCollapsed.value
  window.localStorage.setItem(asideStorageKey, isAsideCollapsed.value ? '1' : '0')
}

async function handleLogout() {
  await userStore.logout()
  router.push('/login')
}
</script>
