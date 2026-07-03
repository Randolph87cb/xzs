import Vue from 'vue'
import Avatar from 'element-ui/lib/avatar'
import Badge from 'element-ui/lib/badge'
import Button from 'element-ui/lib/button'
import Card from 'element-ui/lib/card'
import Carousel from 'element-ui/lib/carousel'
import CarouselItem from 'element-ui/lib/carousel-item'
import Checkbox from 'element-ui/lib/checkbox'
import CheckboxGroup from 'element-ui/lib/checkbox-group'
import Col from 'element-ui/lib/col'
import Collapse from 'element-ui/lib/collapse'
import CollapseItem from 'element-ui/lib/collapse-item'
import Container from 'element-ui/lib/container'
import DatePicker from 'element-ui/lib/date-picker'
import Dialog from 'element-ui/lib/dialog'
import Divider from 'element-ui/lib/divider'
import Dropdown from 'element-ui/lib/dropdown'
import DropdownItem from 'element-ui/lib/dropdown-item'
import DropdownMenu from 'element-ui/lib/dropdown-menu'
import Footer from 'element-ui/lib/footer'
import Form from 'element-ui/lib/form'
import FormItem from 'element-ui/lib/form-item'
import Header from 'element-ui/lib/header'
import Input from 'element-ui/lib/input'
import Loading from 'element-ui/lib/loading'
import Main from 'element-ui/lib/main'
import Menu from 'element-ui/lib/menu'
import MenuItem from 'element-ui/lib/menu-item'
import Message from 'element-ui/lib/message'
import MessageBox from 'element-ui/lib/message-box'
import Option from 'element-ui/lib/option'
import Pagination from 'element-ui/lib/pagination'
import Radio from 'element-ui/lib/radio'
import RadioGroup from 'element-ui/lib/radio-group'
import Rate from 'element-ui/lib/rate'
import Row from 'element-ui/lib/row'
import Select from 'element-ui/lib/select'
import TabPane from 'element-ui/lib/tab-pane'
import Table from 'element-ui/lib/table'
import TableColumn from 'element-ui/lib/table-column'
import Tabs from 'element-ui/lib/tabs'
import Tag from 'element-ui/lib/tag'
import Timeline from 'element-ui/lib/timeline'
import TimelineItem from 'element-ui/lib/timeline-item'
import Upload from 'element-ui/lib/upload'
import 'element-ui/lib/theme-chalk/index.css'

const components = [
  Avatar,
  Badge,
  Button,
  Card,
  Carousel,
  CarouselItem,
  Checkbox,
  CheckboxGroup,
  Col,
  Collapse,
  CollapseItem,
  Container,
  DatePicker,
  Dialog,
  Divider,
  Dropdown,
  DropdownItem,
  DropdownMenu,
  Footer,
  Form,
  FormItem,
  Header,
  Input,
  Main,
  Menu,
  MenuItem,
  Option,
  Pagination,
  Radio,
  RadioGroup,
  Rate,
  Row,
  Select,
  TabPane,
  Table,
  TableColumn,
  Tabs,
  Tag,
  Timeline,
  TimelineItem,
  Upload
]

Vue.prototype.$ELEMENT = {
  size: 'medium'
}

components.forEach(component => {
  Vue.use(component)
})

Vue.use(Loading.directive)
Vue.prototype.$loading = Loading.service
Vue.prototype.$message = Message
Vue.prototype.$msgbox = MessageBox
Vue.prototype.$alert = MessageBox.alert
Vue.prototype.$confirm = MessageBox.confirm
Vue.prototype.$prompt = MessageBox.prompt
