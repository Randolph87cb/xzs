<template>
  <main class="login">
    <section class="login__panel">
      <h1>学生考试系统</h1>
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
const form = reactive({
  userName: '',
  password: '',
  remember: false
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

.login__remember {
  margin: -4px 0 16px;
}
</style>
