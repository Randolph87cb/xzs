<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>{{ form.id ? '编辑题组' : '添加题组' }}</h1>
        <p>共享题面只保存一次；子题按下方顺序连续进入试卷。</p>
      </div>
      <div class="admin-page__actions">
        <el-button @click="router.push('/exam/question/group/list')">返回列表</el-button>
        <el-button type="primary" :loading="saving" @click="saveGroup">保存题组</el-button>
      </div>
    </header>

    <el-form ref="formRef" :model="form" :rules="rules" label-width="92px">
      <section class="question-group-edit__meta">
        <el-form-item label="题组类型" prop="groupType">
          <el-select v-model="form.groupType" style="width: 170px">
            <el-option label="程序阅读" :value="1" />
            <el-option label="程序填空" :value="2" />
          </el-select>
        </el-form-item>
        <el-form-item label="学科" prop="subjectId">
          <el-select v-model="form.subjectId" style="width: 210px" @change="syncQuestionSubjects">
            <el-option v-for="subject in subjects" :key="subject.id" :label="subject.name" :value="subject.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="题组编号">
          <el-input v-model="form.groupCode" style="width: 220px" />
        </el-form-item>
        <el-form-item label="难度" prop="difficult">
          <el-rate v-model="form.difficult" />
        </el-form-item>
        <el-form-item label="知识点" prop="knowledgePoint">
          <el-input v-model="form.knowledgePoint" style="width: 220px" />
        </el-form-item>
        <el-form-item label="状态">
          <el-switch v-model="groupEnabled" active-text="启用" inactive-text="停用" />
        </el-form-item>
      </section>

      <el-alert v-if="form.importSource" type="info" :closable="false" show-icon>
        来源：{{ form.importSource }}<span v-if="form.importBatch">（{{ form.importBatch }}）</span>
      </el-alert>

      <section class="question-group-edit__shared">
        <div class="question-group-edit__editor">
          <h2>共享题面</h2>
          <el-form-item prop="title" label-width="0">
            <el-input
              v-model="form.title"
              type="textarea"
              :autosize="{ minRows: 10, maxRows: 24 }"
              placeholder="请输入程序、材料、输入输出说明等共享内容"
            />
          </el-form-item>
        </div>
        <div class="question-group-edit__preview">
          <h2>共享题面预览</h2>
          <QuestionMarkdown :content="form.title" default-language="cpp" />
        </div>
      </section>

      <section class="question-group-edit__children">
        <header>
          <div>
            <h2>有序子题</h2>
            <p>共 {{ form.questionItems.length }} 题，总分 {{ totalScore }}</p>
          </div>
          <el-button type="primary" plain @click="addQuestion">添加子题</el-button>
        </header>

        <el-card
          v-for="(question, questionIndex) in form.questionItems"
          :key="question.id || questionKey(question)"
          class="question-group-edit__child"
          shadow="never"
        >
          <template #header>
            <div class="question-group-edit__child-header">
              <div>
                <strong>第 {{ questionIndex + 1 }} 小题</strong>
                <span v-if="question.id">题目 #{{ question.id }}</span>
              </div>
              <div class="admin-page__actions">
                <el-button size="small" :disabled="questionIndex === 0" @click="moveQuestion(questionIndex, -1)">上移</el-button>
                <el-button
                  size="small"
                  :disabled="questionIndex === form.questionItems.length - 1"
                  @click="moveQuestion(questionIndex, 1)"
                >下移</el-button>
                <el-button size="small" type="danger" @click="removeQuestion(questionIndex)">删除</el-button>
              </div>
            </div>
          </template>

          <div class="question-group-edit__child-meta">
            <el-form-item label="题型" required>
              <el-select
                v-model="question.questionType"
                :disabled="Boolean(question.id)"
                style="width: 150px"
                @change="handleQuestionTypeChange(question)"
              >
                <el-option v-for="type in questionTypes" :key="type.value" :label="type.label" :value="type.value" />
              </el-select>
            </el-form-item>
            <el-form-item label="分数" required>
              <el-input v-model="question.score" style="width: 100px" />
            </el-form-item>
            <el-form-item label="难度" required>
              <el-rate v-model="question.difficult" />
            </el-form-item>
            <el-form-item label="知识点" required>
              <el-input v-model="question.knowledgePoint" style="width: 190px" />
            </el-form-item>
          </div>

          <div class="question-group-edit__two-columns">
            <section>
              <h3>子题题干</h3>
              <el-input v-model="question.title" type="textarea" :autosize="{ minRows: 4, maxRows: 12 }" />
            </section>
            <section class="question-group-edit__content-preview">
              <h3>题干预览</h3>
              <QuestionMarkdown :content="question.title" default-language="cpp" />
            </section>
          </div>

          <section v-if="question.questionType !== 5" class="question-group-edit__options">
            <header>
              <h3>{{ question.questionType === 4 ? '填空答案与分值' : '选项' }}</h3>
              <el-button size="small" @click="addOption(question)">添加{{ question.questionType === 4 ? '空' : '选项' }}</el-button>
            </header>
            <div v-for="(item, itemIndex) in question.items" :key="item.itemUuid ?? `${item.prefix}-${itemIndex}`" class="question-group-edit__option">
              <el-input v-model="item.prefix" class="question-group-edit__option-prefix" />
              <el-input
                v-model="item.content"
                type="textarea"
                :autosize="{ minRows: 2, maxRows: 8 }"
                :placeholder="question.questionType === 4 ? '该空正确答案' : '选项内容'"
              />
              <el-input v-if="question.questionType === 4" v-model="item.score" placeholder="分值" class="question-group-edit__option-score" />
              <el-button text type="danger" @click="question.items.splice(itemIndex, 1)">删除</el-button>
            </div>
          </section>

          <el-form-item v-if="question.questionType === 2" label="正确答案" required>
            <el-checkbox-group v-model="question.correctArray">
              <el-checkbox v-for="item in question.items" :key="item.prefix" :value="item.prefix">{{ item.prefix }}</el-checkbox>
            </el-checkbox-group>
          </el-form-item>
          <el-form-item v-else-if="question.questionType === 1 || question.questionType === 3" label="正确答案" required>
            <el-select v-model="question.correct" style="width: 150px">
              <el-option v-for="item in question.items" :key="item.prefix" :label="item.prefix" :value="item.prefix" />
            </el-select>
          </el-form-item>
          <el-form-item v-else-if="question.questionType === 5" label="参考答案" required>
            <el-input v-model="question.correct" type="textarea" :rows="3" />
          </el-form-item>

          <div class="question-group-edit__two-columns">
            <section>
              <h3>解析</h3>
              <el-input v-model="question.analyze" type="textarea" :autosize="{ minRows: 4, maxRows: 12 }" />
            </section>
            <section class="question-group-edit__content-preview">
              <h3>解析预览</h3>
              <QuestionMarkdown :content="question.analyze" default-language="cpp" />
            </section>
          </div>
        </el-card>

        <el-empty v-if="form.questionItems.length === 0" description="请至少添加一个子题" />
      </section>
    </el-form>
  </section>
</template>

<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox, type FormInstance, type FormRules } from 'element-plus'
import { QuestionMarkdown } from '@xzs/question-renderer'
import { useRoute, useRouter } from 'vue-router'
import {
  getAdminQuestionGroup,
  getAdminSubjectPage,
  saveAdminQuestionGroup,
  type AdminQuestionEditItem,
  type AdminQuestionEditModel,
  type AdminQuestionGroupEditModel,
  type AdminSubjectListItem
} from '@xzs/api-client'

const route = useRoute()
const router = useRouter()
const formRef = ref<FormInstance>()
const loading = ref(false)
const saving = ref(false)
const subjects = ref<AdminSubjectListItem[]>([])
const form = reactive<AdminQuestionGroupEditModel>({
  id: null,
  groupType: 1,
  subjectId: 1,
  difficult: 1,
  knowledgePoint: '综合',
  title: '',
  groupCode: null,
  status: 1,
  questionItems: []
})
const rules: FormRules = {
  groupType: [{ required: true, message: '请选择题组类型', trigger: 'change' }],
  subjectId: [{ required: true, message: '请选择学科', trigger: 'change' }],
  difficult: [{ required: true, message: '请选择难度', trigger: 'change' }],
  knowledgePoint: [{ required: true, message: '请输入知识点', trigger: 'blur' }],
  title: [{ required: true, message: '请输入共享题面', trigger: 'blur' }]
}
const questionTypes = [
  { value: 1, label: '单选题' },
  { value: 2, label: '多选题' },
  { value: 3, label: '判断题' },
  { value: 4, label: '填空题' },
  { value: 5, label: '简答题' }
]
const questionKeys = new WeakMap<AdminQuestionEditModel, string>()
const totalScore = computed(() =>
  form.questionItems.reduce((sum, question) => sum + (Number(question.score) || 0), 0)
)
const groupEnabled = computed({
  get: () => form.status !== 0,
  set: (enabled: boolean) => {
    form.status = enabled ? 1 : 0
  }
})

loadPage()

async function loadPage() {
  loading.value = true
  try {
    const subjectResult = await getAdminSubjectPage({ pageIndex: 1, pageSize: 100 })
    subjects.value = subjectResult.response?.list ?? []
    if (subjects.value[0] && !subjects.value.some((subject) => subject.id === form.subjectId)) {
      form.subjectId = subjects.value[0].id
    }

    const id = Number(route.query.id || 0)
    if (id) {
      const result = await getAdminQuestionGroup(id)
      if (result.response) {
        Object.assign(form, normalizeGroup(result.response))
      }
    } else if (form.questionItems.length === 0) {
      addQuestion()
    }
  } finally {
    loading.value = false
  }
}

async function saveGroup() {
  const valid = await formRef.value?.validate().catch(() => false)
  if (!valid || !validateQuestions()) return

  saving.value = true
  try {
    const result = await saveAdminQuestionGroup(createPayload())
    if (result.code === 1) {
      ElMessage.success(result.message || '题组保存成功')
      router.push('/exam/question/group/list')
    } else {
      ElMessage.error(result.message)
    }
  } finally {
    saving.value = false
  }
}

function validateQuestions() {
  if (form.status === 1 && form.questionItems.length === 0) {
    ElMessage.error('启用题组至少需要一个子题')
    return false
  }

  for (let index = 0; index < form.questionItems.length; index += 1) {
    const question = form.questionItems[index]
    if (!question.title?.trim() || !question.analyze?.trim() || !question.score || !question.knowledgePoint?.trim()) {
      ElMessage.error(`请完整填写第 ${index + 1} 小题的题干、解析、分数和知识点`)
      return false
    }
    if (question.questionType !== 5 && question.items.length === 0) {
      ElMessage.error(`第 ${index + 1} 小题至少需要一个选项或填空`)
      return false
    }
    if (question.questionType !== 5 && question.items.some((item) => !item.prefix?.trim() || !item.content?.trim())) {
      ElMessage.error(`请完整填写第 ${index + 1} 小题的选项编号和内容`)
      return false
    }
    if (question.questionType === 2 && !question.correctArray?.length) {
      ElMessage.error(`请选择第 ${index + 1} 小题的正确答案`)
      return false
    }
    if ([1, 3, 5].includes(question.questionType) && !question.correct?.trim()) {
      ElMessage.error(`请填写第 ${index + 1} 小题的正确答案`)
      return false
    }
    const optionPrefixes = new Set(question.items.map((item) => item.prefix))
    if ([1, 3].includes(question.questionType) && !optionPrefixes.has(question.correct ?? '')) {
      ElMessage.error(`第 ${index + 1} 小题的正确答案必须来自现有选项`)
      return false
    }
    if (question.questionType === 2 && question.correctArray?.some((answer) => !optionPrefixes.has(answer))) {
      ElMessage.error(`第 ${index + 1} 小题的正确答案包含已删除选项`)
      return false
    }
    if (question.questionType === 4) {
      if (question.items.some((item) => !item.score || Number(item.score) <= 0)) {
        ElMessage.error(`请填写第 ${index + 1} 小题每个空的有效分值`)
        return false
      }
      const blankScore = question.items.reduce((sum, item) => sum + (Number(item.score) || 0), 0)
      if (blankScore !== Number(question.score)) {
        ElMessage.error(`第 ${index + 1} 小题各空分值之和必须等于题目分数`)
        return false
      }
    }
  }
  return true
}

function createPayload(): AdminQuestionGroupEditModel {
  return {
    ...form,
    questionItems: form.questionItems.map((question, index) => ({
      ...question,
      subjectId: form.subjectId,
      groupItemOrder: index + 1,
      items: question.items.map((item) => ({ ...item })),
      correctArray: [...(question.correctArray ?? [])],
      correct: question.questionType === 2 ? (question.correctArray ?? []).join(',') : question.correct
    }))
  }
}

function normalizeGroup(group: AdminQuestionGroupEditModel): AdminQuestionGroupEditModel {
  return {
    ...group,
    status: group.status ?? 1,
    questionItems: (group.questionItems ?? [])
      .map(normalizeQuestion)
      .sort((left, right) => (left.groupItemOrder ?? 0) - (right.groupItemOrder ?? 0))
  }
}

function normalizeQuestion(question: AdminQuestionEditModel): AdminQuestionEditModel {
  return {
    ...question,
    items: (question.items ?? []).map((item) => ({ ...item, itemUuid: item.itemUuid || createItemUuid() })),
    correctArray: [...(question.correctArray ?? [])],
    correct: question.correct ?? '',
    knowledgePoint: question.knowledgePoint || form.knowledgePoint || '综合'
  }
}

function addQuestion() {
  form.questionItems.push(createQuestion(form.questionItems.length + 1))
}

function createQuestion(order: number): AdminQuestionEditModel {
  return {
    id: null,
    questionType: 1,
    subjectId: form.subjectId,
    title: '',
    items: createChoiceOptions(),
    analyze: '暂无解析',
    correctArray: [],
    correct: 'A',
    score: '5',
    difficult: form.difficult || 1,
    knowledgePoint: form.knowledgePoint || '综合',
    groupItemOrder: order
  }
}

function removeQuestion(index: number) {
  ElMessageBox.confirm('确认从题组中删除该子题？保存后该题将解除题组归属。', '删除子题', { type: 'warning' })
    .then(() => form.questionItems.splice(index, 1))
    .catch(() => undefined)
}

function moveQuestion(index: number, offset: number) {
  const target = index + offset
  if (target < 0 || target >= form.questionItems.length) return
  const [question] = form.questionItems.splice(index, 1)
  form.questionItems.splice(target, 0, question)
}

function addOption(question: AdminQuestionEditModel) {
  if (question.questionType === 4) {
    const prefix = String(question.items.length + 1)
    question.items.push({ prefix, content: '', score: '1', itemUuid: createItemUuid() })
    return
  }
  const prefix = String.fromCharCode(65 + question.items.length)
  question.items.push({ prefix, content: `选项 ${prefix}`, itemUuid: createItemUuid() })
}

function handleQuestionTypeChange(question: AdminQuestionEditModel) {
  if (question.questionType === 3) {
    question.items = [
      { prefix: 'A', content: '正确', itemUuid: createItemUuid() },
      { prefix: 'B', content: '错误', itemUuid: createItemUuid() }
    ]
    question.correct = 'A'
    question.correctArray = []
  } else if (question.questionType === 4) {
    question.items = [{ prefix: '1', content: '', score: question.score || '5', itemUuid: createItemUuid() }]
    question.correct = ''
    question.correctArray = []
  } else if (question.questionType === 5) {
    question.items = []
    question.correct = ''
    question.correctArray = []
  } else {
    question.items = createChoiceOptions()
    question.correct = question.questionType === 1 ? 'A' : ''
    question.correctArray = []
  }
}

function createChoiceOptions(): AdminQuestionEditItem[] {
  return ['A', 'B', 'C', 'D'].map((prefix) => ({
    prefix,
    content: `选项 ${prefix}`,
    itemUuid: createItemUuid()
  }))
}

function createItemUuid() {
  return `admin-${Date.now()}-${Math.random().toString(16).slice(2)}`
}

function questionKey(question: AdminQuestionEditModel) {
  const existing = questionKeys.get(question)
  if (existing) return existing
  const key = createItemUuid()
  questionKeys.set(question, key)
  return key
}

function syncQuestionSubjects() {
  form.questionItems.forEach((question) => {
    question.subjectId = form.subjectId
  })
}
</script>

<style scoped lang="scss">
.question-group-edit__meta,
.question-group-edit__child-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 0 12px;
}

.question-group-edit__shared,
.question-group-edit__two-columns {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(320px, 0.9fr);
  gap: 16px;
  margin-top: 18px;
}

.question-group-edit__editor,
.question-group-edit__preview,
.question-group-edit__content-preview {
  min-width: 0;
}

.question-group-edit__preview,
.question-group-edit__content-preview {
  padding: 12px 14px;
  border: 1px solid var(--el-border-color);
  border-radius: 6px;
  background: var(--el-fill-color-blank);
}

.question-group-edit__shared h2,
.question-group-edit__children h2,
.question-group-edit__children h3 {
  margin: 0 0 10px;
}

.question-group-edit__children {
  display: grid;
  gap: 14px;
  margin-top: 22px;
}

.question-group-edit__children > header,
.question-group-edit__child-header,
.question-group-edit__options > header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.question-group-edit__children > header p {
  margin: 4px 0 0;
  color: var(--el-text-color-secondary);
}

.question-group-edit__child-header > div:first-child {
  display: flex;
  align-items: baseline;
  gap: 10px;
}

.question-group-edit__child-header span {
  color: var(--el-text-color-secondary);
  font-size: 13px;
}

.question-group-edit__two-columns section {
  min-width: 0;
}

.question-group-edit__options {
  display: grid;
  gap: 10px;
  margin-top: 16px;
}

.question-group-edit__option {
  display: grid;
  grid-template-columns: 72px minmax(0, 1fr) 100px auto;
  gap: 10px;
  align-items: start;
}

.question-group-edit__option-prefix,
.question-group-edit__option-score {
  width: 100%;
}

@media (max-width: 960px) {
  .question-group-edit__shared,
  .question-group-edit__two-columns,
  .question-group-edit__option {
    grid-template-columns: 1fr;
  }
}
</style>
