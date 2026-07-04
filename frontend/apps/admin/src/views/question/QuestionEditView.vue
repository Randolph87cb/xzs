<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>题目编辑</h1>
        <p>使用 Vue 3 UEditor wrapper 编辑历史 HTML，并复用学生端 renderer 预览。</p>
      </div>
      <div class="admin-page__actions">
        <el-button data-testid="question-edit-back" @click="router.push('/exam/question/list')">返回列表</el-button>
        <el-button data-testid="question-edit-save" type="primary" :loading="saving" @click="saveQuestion">保存题目</el-button>
      </div>
    </header>

    <el-form ref="formRef" class="question-edit" :model="form" :rules="rules" label-width="92px">
      <section class="question-edit__meta">
        <el-form-item label="题型" prop="questionType">
          <el-select v-model="form.questionType" :disabled="Boolean(form.id)" style="width: 180px">
            <el-option v-for="item in questionTypes" :key="item.value" :label="item.label" :value="item.value" />
          </el-select>
        </el-form-item>
        <el-form-item label="学科" prop="subjectId">
          <el-select v-model="form.subjectId" style="width: 220px">
            <el-option v-for="item in subjects" :key="item.id" :label="item.name" :value="item.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="分数" prop="score">
          <el-input v-model="form.score" style="width: 120px" />
        </el-form-item>
        <el-form-item label="难度" prop="difficult">
          <el-rate v-model="form.difficult" />
        </el-form-item>
        <el-form-item label="知识点" prop="knowledgePoint">
          <el-input v-model="form.knowledgePoint" data-testid="question-edit-knowledge-point" style="width: 220px" />
        </el-form-item>
      </section>

      <section class="question-edit__grid">
        <article>
          <h2>题干</h2>
          <UeditorField v-model="form.title" />
        </article>
        <article>
          <h2>题干预览</h2>
          <div class="question-edit__preview">
            <QuestionMarkdown :content="form.title" />
          </div>
        </article>
      </section>

      <section v-if="form.questionType !== 5" class="question-edit__options">
        <header>
          <h2>选项</h2>
          <el-button size="small" @click="addOption">添加选项</el-button>
        </header>
        <div v-for="(item, index) in form.items" :key="item.itemUuid ?? item.prefix" class="question-edit__option">
          <el-input v-model="item.prefix" style="width: 72px" />
          <el-input v-model="item.content" type="textarea" :rows="2" />
          <el-button text type="danger" @click="removeOption(index)">删除</el-button>
        </div>
      </section>

      <section class="question-edit__grid">
        <article>
          <h2>解析</h2>
          <UeditorField v-model="form.analyze" />
        </article>
        <article>
          <h2>解析预览</h2>
          <div class="question-edit__preview">
            <QuestionMarkdown :content="form.analyze" />
          </div>
        </article>
      </section>

      <section class="question-edit__answer">
        <el-form-item label="答案">
          <el-checkbox-group v-if="form.questionType === 2" v-model="form.correctArray">
            <el-checkbox v-for="item in form.items" :key="item.prefix" :value="item.prefix">{{ item.prefix }}</el-checkbox>
          </el-checkbox-group>
          <el-select v-else-if="form.questionType === 1 || form.questionType === 3" v-model="form.correct" style="width: 160px">
            <el-option v-for="item in form.items" :key="item.prefix" :label="item.prefix" :value="item.prefix" />
          </el-select>
          <el-input v-else v-model="form.correct" type="textarea" :rows="3" />
        </el-form-item>
      </section>
    </el-form>
  </section>
</template>

<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { QuestionMarkdown } from '@xzs/question-renderer'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import { useRoute, useRouter } from 'vue-router'
import {
  getAdminQuestion,
  getAdminSubjectPage,
  saveAdminQuestion,
  type AdminQuestionEditItem,
  type AdminQuestionEditModel,
  type AdminSubjectListItem
} from '@xzs/api-client'
import UeditorField from '@/components/UeditorField.vue'

const route = useRoute()
const router = useRouter()
const formRef = ref<FormInstance>()
const loading = ref(false)
const saving = ref(false)
const subjects = ref<AdminSubjectListItem[]>([])
const form = reactive<AdminQuestionEditModel>({
  id: null,
  questionType: 1,
  subjectId: 1,
  title: '<p>请输入题干</p>',
  items: createDefaultOptions(),
  analyze: '<p>暂无解析</p>',
  correctArray: [],
  correct: 'A',
  score: '5',
  difficult: 1,
  knowledgePoint: '综合'
})
const questionTypes = [
  { value: 1, label: '单选题' },
  { value: 2, label: '多选题' },
  { value: 3, label: '判断题' },
  { value: 4, label: '填空题' },
  { value: 5, label: '简答题' }
]
const rules: FormRules = {
  questionType: [{ required: true, message: '请选择题型', trigger: 'change' }],
  subjectId: [{ required: true, message: '请选择学科', trigger: 'change' }],
  title: [{ required: true, message: '请输入题干', trigger: 'blur' }],
  analyze: [{ required: true, message: '请输入解析', trigger: 'blur' }],
  score: [{ required: true, message: '请输入分数', trigger: 'blur' }],
  difficult: [{ required: true, message: '请选择难度', trigger: 'change' }],
  knowledgePoint: [{ required: true, message: '请输入知识点', trigger: 'blur' }]
}
const questionId = computed(() => Number(route.query.id))

watch(
  () => form.questionType,
  (type) => {
    if (type === 3) {
      form.items = [
        { prefix: 'A', content: '正确' },
        { prefix: 'B', content: '错误' }
      ]
      form.correct = form.correct === 'B' ? 'B' : 'A'
    } else if (type === 5) {
      form.items = []
    } else if (form.items.length === 0) {
      form.items = createDefaultOptions()
    }
  }
)

loadSubjects()
loadQuestion()

async function loadSubjects() {
  const result = await getAdminSubjectPage({ pageIndex: 1, pageSize: 100 })
  subjects.value = result.response?.list ?? []
  if (!form.subjectId && subjects.value[0]) {
    form.subjectId = subjects.value[0].id
  }
}

async function loadQuestion() {
  if (!questionId.value) {
    return
  }

  loading.value = true
  try {
    const result = await getAdminQuestion(questionId.value)
    if (result.response) {
      Object.assign(form, normalizeQuestion(result.response))
    }
  } finally {
    loading.value = false
  }
}

async function saveQuestion() {
  const valid = await formRef.value?.validate().catch(() => false)
  if (!valid) {
    return
  }

  saving.value = true
  try {
    const payload = normalizeForSubmit(form)
    const result = await saveAdminQuestion(payload)
    if (result.code === 1) {
      ElMessage.success(result.message)
      router.push('/exam/question/list')
    } else {
      ElMessage.error(result.message)
    }
  } finally {
    saving.value = false
  }
}

function addOption() {
  const prefix = String.fromCharCode(65 + form.items.length)
  form.items.push({ prefix, content: `选项 ${prefix}` })
}

function removeOption(index: number) {
  form.items.splice(index, 1)
}

function createDefaultOptions(): AdminQuestionEditItem[] {
  return ['A', 'B', 'C', 'D'].map((prefix) => ({ prefix, content: `选项 ${prefix}` }))
}

function normalizeQuestion(question: AdminQuestionEditModel): AdminQuestionEditModel {
  return {
    ...question,
    items: question.items ?? [],
    correctArray: question.correctArray ?? [],
    correct: question.correct ?? '',
    knowledgePoint: question.knowledgePoint ?? '综合'
  }
}

function normalizeForSubmit(question: AdminQuestionEditModel): AdminQuestionEditModel {
  const payload = normalizeQuestion(question)
  if (payload.questionType === 2) {
    payload.correct = payload.correctArray?.join(',')
  }
  return payload
}
</script>
