<template>
  <main class="admin-login">
    <el-form ref="formRef" class="admin-login__form" :model="form" :rules="rules" @submit.prevent="handleLogin">
      <div class="admin-login__brand">
        <img class="admin-login__brand-icon" :src="appIconUrl" alt="" />
        <div>
          <h1>信息学客观题一本通</h1>
          <p>GESP/CSP 客观题智能组卷与错题审核平台</p>
        </div>
      </div>
      <el-form-item prop="userName">
        <el-input v-model="form.userName" autocomplete="username" placeholder="用户名" />
      </el-form-item>
      <el-form-item prop="password">
        <el-input
          v-model="form.password"
          autocomplete="current-password"
          placeholder="密码"
          show-password
          type="password"
          @keyup.enter="handleLogin"
        />
      </el-form-item>
      <el-checkbox v-model="form.remember">保持登录</el-checkbox>
      <el-button class="admin-login__button" type="primary" native-type="submit" :loading="loading" @click="handleLogin">
        登录
      </el-button>
    </el-form>
  </main>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import { useRoute, useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'

const router = useRouter()
const route = useRoute()
const userStore = useUserStore()
const formRef = ref<FormInstance>()
const loading = ref(false)
const appIconUrl = `${import.meta.env.BASE_URL}app-icon.svg`
const form = reactive({
  userName: '',
  password: '',
  remember: true
})
const rules: FormRules = {
  userName: [
    { required: true, message: '请输入用户名', trigger: 'blur' },
    { min: 5, message: '用户名不能少于 5 个字符', trigger: 'blur' }
  ],
  password: [
    { required: true, message: '请输入密码', trigger: 'blur' },
    { min: 5, message: '密码不能少于 5 个字符', trigger: 'blur' }
  ]
}

async function handleLogin() {
  const valid = await formRef.value?.validate().catch(() => false)
  if (!valid || loading.value) {
    return
  }

  loading.value = true
  try {
    const result = await userStore.login(form)
    if (result.code === 1) {
      const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : '/dashboard'
      router.push(redirect)
    } else {
      ElMessage.error(result.message)
    }
  } finally {
    loading.value = false
  }
}
</script>
