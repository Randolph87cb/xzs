import {
  formatSeconds,
} from '../../../utils/util.js'
import {
  mapAnswerItemsByOrder,
  normalizeExamPaper
} from '../../../utils/exam-paper.js'

let app = getApp()
Page({
  data: {
    spinShow: false,
    paperId: null,
    paper: {},
    answer: {},
    answerByOrder: [],
    timer: null,
    doTime: 0,
    remainTime: 0,
    remainTimeStr: '',
    modalShow: false,
    result: 0,
    timeOutShow: false
  },
  onLoad: function(options) {
    let paperId = options.id
    let _this = this
    _this.setData({
      spinShow: true
    });
    app.formPost('/api/wx/student/exampaper/answer/read/' + paperId, null)
      .then(res => {
        _this.setData({
          spinShow: false
        });
        if (res.code === 1) {
          _this.setData({
            paper: normalizeExamPaper(res.response.paper),
            answer: res.response.answer,
            answerByOrder: mapAnswerItemsByOrder(res.response.answer.answerItems),
            paperId: paperId,
          });
        }
      }).catch(e => {
        _this.setData({
          spinShow: false
        });
        app.message(e, 'error')
      })
  },
  onUnload() {
    clearInterval(this.data.timer)
  },
  returnRecord() {
    wx.reLaunch({
      url: '/pages/record/index',
    });
  },
  timeOut() {
    clearInterval(this.data.timer)
    this.setData({
      timeOutShow: true
    });
  }
})
