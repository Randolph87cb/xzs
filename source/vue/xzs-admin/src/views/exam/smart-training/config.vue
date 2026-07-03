<template>
  <div class="app-container">
    <el-form :inline="true">
      <el-form-item label="学科：">
        <el-select v-model="selectedSubjectId" placeholder="请选择学科" @change="handleSubjectChange">
          <el-option v-for="item in subjectFilter" :key="item.id" :value="item.id" :label="item.name"></el-option>
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" :disabled="selectedSubjectId === null" @click="loadSubjectConfig">加载配置</el-button>
      </el-form-item>
    </el-form>

    <el-form :model="form" ref="form" label-width="120px" v-loading="formLoading" :rules="rules">
      <el-form-item label="总题数：" prop="questionCount" required>
        <el-input-number v-model="form.questionCount" :min="1" :step="1" :precision="0"></el-input-number>
      </el-form-item>
      <el-form-item label="知识点配比：">
        <el-table :data="form.rules" border fit style="width: 100%">
          <el-table-column label="知识点">
            <template slot-scope="{row}">
              <el-select v-model="row.knowledgePoint" filterable allow-create default-first-option placeholder="请选择或输入知识点">
                <el-option v-for="item in knowledgePoints" :key="item" :value="item" :label="item"></el-option>
              </el-select>
            </template>
          </el-table-column>
          <el-table-column label="题数" width="180px">
            <template slot-scope="{row}">
              <el-input-number v-model="row.questionCount" :min="1" :step="1" :precision="0"></el-input-number>
            </template>
          </el-table-column>
          <el-table-column label="操作" align="center" width="100px">
            <template slot-scope="{$index}">
              <el-button type="danger" size="mini" icon="el-icon-delete" @click="removeRule($index)"></el-button>
            </template>
          </el-table-column>
        </el-table>
        <el-button type="success" class="rule-add-button" @click="addRule">添加知识点</el-button>
      </el-form-item>
      <el-form-item label="配比合计：">
        <span>{{ruleQuestionCount}}</span>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" :disabled="form.subjectId === null" @click="submitForm">保存</el-button>
      </el-form-item>
    </el-form>

    <el-table v-loading="listLoading" :data="configList" border fit highlight-current-row style="width: 100%">
      <el-table-column prop="id" label="Id" width="90px"/>
      <el-table-column prop="subjectId" label="学科" :formatter="subjectFormatter" width="160px"/>
      <el-table-column prop="questionCount" label="总题数" width="100px"/>
      <el-table-column label="操作" align="center" width="120px">
        <template slot-scope="{row}">
          <el-button size="mini" @click="selectConfig(row)">编辑</el-button>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script>
import { mapState, mapActions } from 'vuex'
import smartTrainingApi from '@/api/smartTraining'

export default {
  data () {
    return {
      selectedSubjectId: null,
      subjectFilter: null,
      knowledgePoints: [],
      formLoading: false,
      listLoading: false,
      configList: [],
      form: this.defaultForm(),
      rules: {
        questionCount: [
          { required: true, message: '请输入总题数', trigger: 'blur' }
        ]
      }
    }
  },
  created () {
    let _this = this
    this.initSubject(function () {
      _this.subjectFilter = _this.subjects
    })
    this.loadConfigList()
  },
  methods: {
    defaultForm () {
      return {
        id: null,
        subjectId: null,
        questionCount: 20,
        rules: [
          {
            knowledgePoint: '综合',
            questionCount: 20
          }
        ]
      }
    },
    handleSubjectChange () {
      this.loadSubjectConfig()
      this.loadKnowledgePoints()
    },
    loadConfigList () {
      this.listLoading = true
      smartTrainingApi.configList({}).then(re => {
        this.configList = re.response || []
        this.listLoading = false
      }).catch(e => {
        this.listLoading = false
      })
    },
    loadKnowledgePoints () {
      this.knowledgePoints = []
      if (this.selectedSubjectId === null) {
        return
      }
      smartTrainingApi.knowledgePoints(this.selectedSubjectId).then(re => {
        this.knowledgePoints = re.response || []
      })
    },
    loadSubjectConfig () {
      if (this.selectedSubjectId === null) {
        this.form = this.defaultForm()
        return
      }
      this.formLoading = true
      smartTrainingApi.configSelect(this.selectedSubjectId).then(re => {
        let response = re.response || this.defaultForm()
        response.subjectId = this.selectedSubjectId
        response.rules = response.rules || []
        this.form = response
        this.formLoading = false
      }).catch(e => {
        this.formLoading = false
      })
    },
    selectConfig (row) {
      this.selectedSubjectId = row.subjectId
      this.loadKnowledgePoints()
      this.loadSubjectConfig()
    },
    addRule () {
      this.form.rules.push({
        knowledgePoint: '',
        questionCount: 1
      })
    },
    removeRule (index) {
      this.form.rules.splice(index, 1)
    },
    submitForm () {
      if (!this.validateRules()) {
        return
      }
      this.formLoading = true
      smartTrainingApi.configEdit(this.form).then(re => {
        if (re.code === 1) {
          this.$message.success(re.message)
          this.loadConfigList()
        } else {
          this.$message.error(re.message)
        }
        this.formLoading = false
      }).catch(e => {
        this.formLoading = false
      })
    },
    validateRules () {
      if (this.form.subjectId === null) {
        this.$message.error('请选择学科')
        return false
      }
      if (this.form.questionCount === null || this.form.questionCount < 1) {
        this.$message.error('请输入总题数')
        return false
      }
      for (let item of this.form.rules) {
        if (!item.knowledgePoint) {
          this.$message.error('请选择或输入知识点')
          return false
        }
        if (item.questionCount === null || item.questionCount < 1) {
          this.$message.error('请输入知识点题数')
          return false
        }
      }
      if (this.ruleQuestionCount !== this.form.questionCount) {
        this.$message.error('知识点配比题数合计需等于总题数')
        return false
      }
      return true
    },
    subjectFormatter (row, column, cellValue, index) {
      let subject = this.subjects.find(item => item.id === cellValue)
      return subject ? subject.name : null
    },
    ...mapActions('exam', { initSubject: 'initSubject' })
  },
  computed: {
    ruleQuestionCount () {
      return this.form.rules.reduce((total, item) => total + (item.questionCount || 0), 0)
    },
    ...mapState('exam', { subjects: state => state.subjects })
  }
}
</script>

<style scoped>
.rule-add-button {
  margin-top: 10px;
}
</style>
