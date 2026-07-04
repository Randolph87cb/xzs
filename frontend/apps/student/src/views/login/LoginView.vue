<template>
  <main class="login">
    <section class="login__panel">
      <h1>学生考试系统</h1>
      <el-form label-position="top" class="login__form">
        <el-form-item label="用户名">
          <el-input v-model="form.userName" autocomplete="username" />
        </el-form-item>
        <el-form-item label="密码">
          <el-input v-model="form.password" type="password" autocomplete="current-password" />
        </el-form-item>
        <el-button type="primary" class="login__button" @click="handleLocalLogin">登录</el-button>
      </el-form>
    </section>
  </main>
</template>

<script setup lang="ts">
import { reactive } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'

const router = useRouter()
const userStore = useUserStore()
const form = reactive({
  userName: '',
  password: ''
})

function handleLocalLogin() {
  userStore.setUserName(form.userName)
  router.push('/index')
}
</script>

<style scoped lang="scss">
.login {
  display: grid;
  min-height: 100vh;
  place-items: center;
  padding: 24px;
}

.login__panel {
  width: min(360px, 100%);
  padding: 28px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
  box-shadow: 0 16px 40px rgba(15, 23, 42, 0.08);
}

.login__panel h1 {
  margin: 0 0 24px;
  font-size: 22px;
  color: #1f2937;
  text-align: center;
}

.login__button {
  width: 100%;
}
</style>
