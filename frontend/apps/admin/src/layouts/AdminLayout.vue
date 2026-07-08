<template>
  <el-container class="admin-layout">
    <el-aside class="admin-layout__aside" width="232px">
      <div class="admin-layout__brand">
        <span class="admin-layout__mark">S</span>
        <div class="admin-layout__brand-text">
          <strong>学之思</strong>
          <span>考试管理系统</span>
        </div>
      </div>
      <el-menu router :default-active="route.path" class="admin-layout__menu">
        <template v-for="item in adminMenus" :key="item.path">
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
          <div class="admin-layout__title">管理后台</div>
          <nav class="admin-layout__tabs" aria-label="后台视图">
            <RouterLink class="admin-layout__tab" :class="{ 'is-active': route.path === '/dashboard' }" to="/dashboard">数据看板</RouterLink>
            <RouterLink class="admin-layout__tab" :class="{ 'is-active': route.path.startsWith('/exam') }" to="/exam/paper/list">考试管理</RouterLink>
            <RouterLink class="admin-layout__tab" :class="{ 'is-active': route.path.startsWith('/user') }" to="/user/student/list">用户中心</RouterLink>
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
import { computed } from 'vue'
import { Bell, Collection, DataLine, EditPen, QuestionFilled, Reading, Search, Tickets } from '@element-plus/icons-vue'
import { useRoute, useRouter } from 'vue-router'
import { adminMenus, type AdminMenuIconMap } from '@/router'
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
const userInitial = computed(() => (userStore.userInfo?.userName ?? userStore.userName ?? 'A').slice(0, 1).toUpperCase())

async function handleLogout() {
  await userStore.logout()
  router.push('/login')
}
</script>
