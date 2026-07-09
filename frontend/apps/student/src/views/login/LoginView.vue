<template>
  <main class="login">
    <section class="login__panel">
      <div class="login__brand">
        <img class="login__brand-icon" :src="appIconUrl" alt="" />
        <div>
          <h1>信息学客观题一本通</h1>
          <p>GESP/CSP 客观题训练平台</p>
        </div>
      </div>
      <el-form ref="formRef" :model="form" :rules="rules" label-position="top" class="login__form" @keyup.enter="handleLogin">
        <el-form-item label="用户名" prop="userName">
          <el-input v-model="form.userName" autocomplete="username" autofocus />
        </el-form-item>
        <el-form-item label="密码" prop="password">
          <el-input v-model="form.password" type="password" autocomplete="current-password" />
        </el-form-item>
        <el-checkbox v-model="form.remember" class="login__remember">记住登录</el-checkbox>
        <el-button type="primary" class="login__button" :loading="loading" @click="handleLogin">登录</el-button>
      </el-form>
    </section>
  </main>
</template>

<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import { useRoute, useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()
const formRef = ref<FormInstance>()
const loading = ref(false)
const appIconUrl = `${import.meta.env.BASE_URL}app-icon.svg`
const form = reactive({
  userName: '',
  password: '',
  remember: true
})
const rules: FormRules<typeof form> = {
  userName: [
    { required: true, message: '请输入用户名', trigger: 'blur' },
    { min: 5, message: '用户名不能少于5个字符', trigger: 'blur' }
  ],
  password: [
    { required: true, message: '请输入密码', trigger: 'blur' },
    { min: 5, message: '密码不能少于5个字符', trigger: 'blur' }
  ]
}
const redirectPath = computed(() => {
  const redirect = route.query.redirect
  return typeof redirect === 'string' && redirect.startsWith('/') ? redirect : '/index'
})

async function handleLogin() {
  const valid = await formRef.value?.validate()

  if (!valid) {
    return
  }

  loading.value = true
  try {
    await userStore.login(form)
    router.push(redirectPath.value)
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '登录失败')
  } finally {
    loading.value = false
  }
}
</script>

<style scoped lang="scss">
.login {
  display: grid;
  min-height: 100vh;
  place-items: center;
  padding: 24px;
  background:
    linear-gradient(135deg, rgb(23 105 255 / 10%), transparent 42%),
    linear-gradient(315deg, rgb(19 166 107 / 10%), transparent 38%),
    var(--xzs-bg);
}

.login__panel {
  width: min(392px, 100%);
  padding: 32px;
  border: 1px solid var(--xzs-border);
  border-radius: var(--xzs-radius);
  background: rgb(255 255 255 / 92%);
  box-shadow: var(--xzs-shadow);
}

.login__brand {
  display: flex;
  justify-content: center;
  align-items: center;
  gap: 12px;
  margin-bottom: 26px;
}

.login__brand-icon {
  width: 42px;
  height: 42px;
  border-radius: 8px;
  display: block;
  box-shadow: 0 10px 20px rgb(23 105 255 / 24%);
}

.login__brand h1,
.login__brand p {
  margin: 0;
}

.login__brand h1 {
  font-size: 22px;
  color: var(--xzs-text);
}

.login__brand p {
  margin-top: 4px;
  color: var(--xzs-text-muted);
  font-size: 13px;
}

.login__button {
  width: 100%;
}

.login__remember {
  margin: -4px 0 16px;
}
</style>
