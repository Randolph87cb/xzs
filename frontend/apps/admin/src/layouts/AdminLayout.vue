<template>
  <el-container class="admin-layout">
    <el-aside class="admin-layout__aside" width="232px">
      <div class="admin-layout__brand">学之思管理系统</div>
      <el-menu router :default-active="route.path" background-color="#1f2937" text-color="#d1d5db" active-text-color="#fff">
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
        <div class="admin-layout__title">{{ routeTitle }}</div>
        <div class="admin-layout__user">
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
import { Collection, DataLine, EditPen, Reading, Tickets } from '@element-plus/icons-vue'
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
const routeTitle = computed(() => (typeof route.meta.title === 'string' ? route.meta.title : '管理后台'))
const userInitial = computed(() => (userStore.userInfo?.userName ?? userStore.userName ?? 'A').slice(0, 1).toUpperCase())

async function handleLogout() {
  await userStore.logout()
  router.push('/login')
}
</script>
