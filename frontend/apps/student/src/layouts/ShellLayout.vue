<template>
  <el-container class="shell">
    <el-header class="shell__header">
      <div class="shell__brand">学生考试系统</div>
      <el-menu mode="horizontal" router :default-active="$route.path" class="shell__menu">
        <el-menu-item index="/index">首页</el-menu-item>
        <el-menu-item index="/paper/index">试卷中心</el-menu-item>
        <el-menu-item index="/training/index">智能训练</el-menu-item>
        <el-menu-item index="/record/index">考试记录</el-menu-item>
      </el-menu>
      <el-button text @click="handleLogout">退出</el-button>
    </el-header>
    <el-main class="shell__main">
      <RouterView />
    </el-main>
  </el-container>
</template>

<script setup lang="ts">
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'

const router = useRouter()
const userStore = useUserStore()

async function handleLogout() {
  await userStore.logout()
  router.push('/login')
}
</script>

<style scoped lang="scss">
.shell {
  min-height: 100vh;
  background: #f5f7fb;
}

.shell__header {
  display: flex;
  align-items: center;
  gap: 24px;
  padding: 0 24px;
  border-bottom: 1px solid #e5e7eb;
  background: #fff;
}

.shell__brand {
  flex: 0 0 auto;
  font-size: 18px;
  font-weight: 600;
  color: #1f2937;
}

.shell__menu {
  flex: 1 1 auto;
  border-bottom: 0;
}

.shell__main {
  width: min(1120px, calc(100vw - 32px));
  margin: 0 auto;
  padding: 24px 0;
}
</style>
