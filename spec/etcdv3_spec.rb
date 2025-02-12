require 'spec_helper'

describe Etcdv3 do
  let(:lease_stub) { local_stub(Etcdv3::Lease, 1) }

  context 'Insecure connection without Auth' do
    let(:conn) { local_connection }

    describe '#initialize' do
      context 'without auth' do
        subject { conn }
        it { is_expected.to have_attributes(token: nil) }
        it { is_expected.to have_attributes(user: nil) }
        it { is_expected.to have_attributes(password: nil) }
      end
      context 'with auth' do
        let(:auth_conn) { local_connection_with_auth('test', 'pass') }
        before do
          conn.user_add('root', 'pass')
          conn.user_grant_role('root', 'root')
          conn.user_add('test', 'pass')
          conn.auth_enable
        end
        after do
          conn.authenticate('root', 'pass')
          conn.auth_disable
          conn.user_delete('root')
          conn.user_delete('test')
        end
        it 'doesnt raise error' do
          expect{ auth_conn }.to_not raise_error
        end
      end
      context 'with a timeout' do
        it "sets the timeout in the kv handler" do
          etcd = local_connection_with_timeout(1.5)
          kv_handler = etcd.conn.connection.instance_variable_get("@handlers")[:kv]
          expect(kv_handler.instance_variable_get "@timeout").to eq(1.5)
        end

        it "sets a default timeout" do
          etcd = local_connection
          kv_handler = etcd.conn.connection.instance_variable_get("@handlers")[:kv]
          expect(kv_handler.instance_variable_get "@timeout").to eq(120)
        end
      end
    end

    describe '#version' do
      subject { conn.version }
      it { is_expected.to be_an_instance_of(String) }
    end

    describe '#db_size' do
      subject { conn.db_size }
      it { is_expected.to_not be_nil }
    end

    describe '#leader_id' do
      subject { conn.leader_id }
      it { is_expected.to_not be_nil }
    end

    describe '#alarm_list' do
      subject { conn.alarm_list }
      it { is_expected.to_not be_nil }
    end

    describe '#alarm_deactivate' do
      subject { conn.alarm_deactivate }
      it { is_expected.to_not be_nil }
    end

    describe '#get' do
      before do
        conn.put('apple', 'test')
        conn.put('applee', 'test')
        conn.put('appleee', 'test')
      end
      context 'no filters' do
        subject { conn.get('apple') }
        it { is_expected.to_not be_nil }
      end
      context 'sorts desc' do
        subject do
          conn.get('apple', range_end: 'appleeee', sort_order: :descend) \
            .kvs.first.key
        end
        it { is_expected.to eq('appleee') }
      end
      context 'sorts asc' do
        subject do
          conn.get('apple', range_end: 'appleeee', sort_order: :ascend) \
            .kvs.first.key
        end
        it { is_expected.to eq('apple') }
      end
      context 'count only' do
        subject do
          conn.get('apple', range_end: 'appleeee', count_only: true).kvs
        end
        it { is_expected.to be_empty }
      end
      it_should_behave_like "Etcdv3 instance using a timeout", :get, 'apple'
    end

    # Locking is not implemented in etcd v3.1.X
    unless $instance.version < Gem::Version.new("3.2.0")
      describe '#lock' do
        let(:lease_id) { lease_stub.lease_grant(10)['ID'] }
        subject { conn.lock('bar', lease_id) }
        it { is_expected.to be_an_instance_of(V3lockpb::LockResponse) }
      end

      describe '#with_lock' do
        let(:lease_id) { lease_stub.lease_grant(10)['ID'] }
        let(:lease_id_2) { lease_stub.lease_grant(15)['ID'] }
        it 'locks' do
          conn.with_lock('foobar', lease_id) do
            expect { conn.lock('foobar', lease_id_2, timeout: 0.1) }
              .to raise_error(GRPC::DeadlineExceeded)
          end
        end
      end
    end

    describe '#put' do
      subject { conn.put('test', 'value') }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :put, 'test', 'value'
    end

    describe '#del' do
      context 'no range' do
        before { conn.put('test', 'value') }
        subject { conn.del('test') }
        it { is_expected.to_not be_nil }
      end
      context 'ranged del' do
        before do
          conn.put('test', 'value')
          conn.put('testt', 'value')
        end
        subject { conn.del('test', range_end: 'testtt') }
        it { is_expected.to_not be_nil }
      end
      it_should_behave_like "Etcdv3 instance using a timeout", :del, 'test'
    end

    describe '#lease_grant' do
      subject { conn.lease_grant(2) }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :lease_grant, 2
    end

    describe '#lease_revoke' do
      let!(:lease_id) { conn.lease_grant(2)['ID'] }
      subject { conn.lease_revoke(lease_id) }
      it { is_expected.to_not be_nil }
      it "raises a GRPC::DeadlineExceeded exception when it takes too long"  do
        expect do
          conn.lease_revoke(lease_id, timeout: 0)
        end.to raise_exception(GRPC::DeadlineExceeded)
      end
      it "accepts a timeout" do
        expect{ conn.lease_revoke(lease_id, timeout: 10) }.to_not raise_exception
      end
    end

    describe '#lease_ttl' do
      let!(:lease_id) { conn.lease_grant(2)['ID'] }
      subject { conn.lease_ttl(lease_id) }
      it { is_expected.to_not be_nil }
      it "raises a GRPC::DeadlineExceeded exception when it takes too long"  do
        expect do
          conn.lease_ttl(lease_id, timeout: 0)
        end.to raise_exception(GRPC::DeadlineExceeded)
      end
      it "accepts a timeout" do
        expect{ conn.lease_ttl(lease_id, timeout: 10) }.to_not raise_exception
      end
    end

    describe '#watch' do
      let!(:foo) { conn.put('foo', 'bar') }
      subject { conn.watch('foo', start_revision: 1) }
      it { is_expected.to_not be_nil }
      it "raises a GRPC::DeadlineExceeded exception when it takes too long"  do
        expect do
          conn.watch('foo', timeout: 0)
        end.to raise_exception(GRPC::DeadlineExceeded)
      end
      it "accepts a timeout" do
        expect{ conn.watch('foo', start_revision: 1, timeout: 10) }.to_not raise_exception
      end
    end

    describe '#lease_keep_alive_once' do
      let!(:lease_id) { conn.lease_grant(2)['ID'] }
      subject { conn.lease_keep_alive_once(lease_id) }
      it { is_expected.to_not be_nil }
      it "raises a GRPC::DeadlineExceeded exception when it takes too long"  do
        expect do
          conn.lease_keep_alive_once(lease_id, timeout: 0)
        end.to raise_exception(GRPC::DeadlineExceeded)
      end
      it "accepts a timeout" do
        expect{ conn.lease_keep_alive_once(lease_id, timeout: 10) }.to_not raise_exception
      end
    end

    describe '#user_add' do
      after { conn.user_delete('test') rescue nil }
      subject { conn.user_add('test', 'user') }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :user_add, 'test', 'user'
    end

    describe '#user_get' do
      after { conn.user_delete('test') rescue nil }
      before { conn.user_add('test', 'user') }
      subject { conn.user_get('test') }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :user_get, 'test'
    end

    describe '#user_delete' do
      before { conn.user_add('test', 'user') rescue nil }
      subject { conn.user_delete('test') }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :user_delete, 'test'
    end

    describe '#user_change_password' do
      before { conn.user_add('change_user', 'pass') }
      after { conn.user_delete('change_user') }
      subject { conn.user_change_password('change_user', 'new_pass') }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :user_change_password, 'change_user', 'new_pass'
    end

    describe '#user_list' do
      subject { conn.user_list }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :user_list
    end

    describe '#role_list' do
      subject { conn.role_list }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :role_list
    end

    describe '#role_add' do
      subject { conn.role_add('role_add') }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :role_add, 'role'
    end

    describe '#role_get' do
      before { conn.role_add('role_get') }
      after { conn.role_delete('role_get') }
      subject { conn.role_get('role_get') }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :role_get, 'role_get'
    end

    describe '#role_delete' do
      before { conn.role_add('role_delete') }
      after { conn.role_delete('role_delete') rescue nil }
      subject { conn.role_delete('role_delete') }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :role_delete, 'role_delete'
    end

    describe '#user_grant_role' do
      before { conn.user_add('grant_me', 'pass') }
      after { conn.user_delete('grant_me') rescue nil}
      subject { conn.user_grant_role('grant_me', 'root') }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :user_grant_role, 'grant_me', 'root'
    end

    describe '#user_revoke_role' do
      before { conn.user_add('grant_me', 'pass') }
      before { conn.user_grant_role('grant_me', 'root') }
      after { conn.user_delete('grant_me') rescue nil}
      subject { conn.user_revoke_role('grant_me', 'root') }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :user_revoke_role, 'grant_me', 'root'
    end

    describe '#role_grant_permission' do
      before { conn.role_add('grant') }
      after { conn.role_delete('grant') }
      subject { conn.role_grant_permission('grant', :readwrite, 'a', **{range_end: 'Z'}) }
      it { is_expected.to_not be_nil }
      it_should_behave_like "Etcdv3 instance using a timeout", :role_grant_permission, 'grant', :readwrite, 'a'
    end

    describe '#role_revoke_permission' do
      before { conn.role_add('grant') }
      before { conn.role_grant_permission('grant', :readwrite, 'a', range_end: 'Z') }
      after { conn.role_delete('grant') }
      subject { conn.role_revoke_permission('grant', :readwrite, 'a', range_end: 'Z') }
      it { is_expected.to_not be_nil }
      describe "the timeouts" do
        before { conn.role_grant_permission('grant', :readwrite, 'a') }
        it_should_behave_like "Etcdv3 instance using a timeout", :role_revoke_permission, 'grant', :readwrite, 'a'
      end
    end

    describe '#auth_disable' do
      before do
        conn.user_add('root', 'test')
        conn.user_grant_role('root', 'root')
        conn.auth_enable
        conn.authenticate('root', 'test')
      end
      after { conn.user_delete('root') }
      after { conn.auth_disable }
      subject { conn.auth_disable }
      it { is_expected.to eq(true) }
      it_should_behave_like "Etcdv3 instance using a timeout", :auth_disable
    end

    describe '#auth_enable' do
      before do
        conn.user_add('root', 'test')
        conn.user_grant_role('root', 'root')
      end
      after do
        conn.authenticate('root', 'test') rescue nil
        conn.auth_disable
        conn.user_delete('root')
      end
      subject { conn.auth_enable }
      it { is_expected.to eq(true) }
      it_should_behave_like "Etcdv3 instance using a timeout", :auth_enable
    end

    describe "#authenticate" do
      context "auth enabled" do
        before do
          conn.user_add('root', 'test')
          conn.user_grant_role('root', 'root')
          conn.auth_enable
          conn.authenticate('root', 'test')
        end
        after do
          conn.auth_disable
          conn.user_delete('root')
        end
        it 'properly reconfigures auth and token' do
          expect(conn.token).to_not be_nil
          expect(conn.user).to eq('root')
          expect(conn.password).to eq('test')
        end
      end

      context 'auth disabled' do
        before do
          conn.user_add('root', 'root')
          conn.auth_disable
        end
        after do
          conn.user_delete('root')
        end
        it 'raises error' do
          expect { conn.authenticate('root', 'root') }.to raise_error(GRPC::FailedPrecondition)
        end
      end
    end

    describe '#transaction' do
      describe 'txn.value' do
        before { conn.put('txn', 'value') }
        after { conn.del('txn') }
        context 'success' do
          subject! do
            conn.transaction do |txn|
              txn.compare = [ txn.value('txn', :equal, 'value') ]
              txn.success = [ txn.put('txn-test', 'success') ]
              txn.failure = [ txn.put('txn-test', 'failed') ]
            end
          end
          it 'sets correct key' do
            expect(conn.get('txn-test').kvs.first.value).to eq('success')
          end
          it "raises a GRPC::DeadlineExceeded exception when it takes too long"  do
            expect do
              conn.transaction(timeout: 0) do |txn|
                txn.compare = [ txn.value('txn', :equal, 'value') ]
                txn.success = [ txn.put('txn-test', 'success') ]
                txn.failure = [ txn.put('txn-test', 'failed') ]
              end
            end.to raise_exception(GRPC::DeadlineExceeded)
          end
          it "accepts a timeout" do
            expect do
              conn.transaction(timeout: 1) do |txn|
                txn.compare = [ txn.value('txn', :equal, 'value') ]
                txn.success = [ txn.put('txn-test', 'success') ]
                txn.failure = [ txn.put('txn-test', 'failed') ]
              end
            end.to_not raise_exception
          end
        end
        context "success, value with lease" do
          let!(:lease_id) { conn.lease_grant(2)['ID'] }
          subject! do
            conn.transaction do |txn|
              txn.compare = [ txn.value('txn', :equal, 'value') ]
              txn.success = [ txn.put('txn-test', 'success', lease_id) ]
              txn.failure = [ txn.put('txn-test', 'failed', lease_id) ]
            end
          end
          it 'sets correct key, with a lease' do
            expect(conn.get('txn-test').kvs.first.value).to eq('success')
            expect(conn.get('txn-test').kvs.first.lease).to eq(lease_id)
          end
        end
        context 'failure' do
          subject! do
            conn.transaction do |txn|
              txn.compare = [ txn.value('txn', :equal, 'notright') ]
              txn.success = [ txn.put('txn-test', 'success') ]
              txn.failure = [ txn.put('txn-test', 'failed') ]
            end
          end
          it 'sets correct key' do
            expect(conn.get('txn-test').kvs.first.value).to eq('failed')
          end
        end
      end

      describe 'txn.create_revision' do
        before { conn.put('txn', 'value') }
        after { conn.del('txn') }
        context 'success' do
          subject! do
            conn.transaction do |txn|
              txn.compare = [ txn.create_revision('txn', :greater, 1) ]
              txn.success = [ txn.put('txn-test', 'success') ]
              txn.failure = [ txn.put('txn-test', 'failed') ]
            end
          end
          it 'sets correct key' do
            expect(conn.get('txn-test').kvs.first.value).to eq('success')
          end
        end
        context 'failure' do
          subject! do
            conn.transaction do |txn|
              txn.compare = [ txn.create_revision('txn', :equal, 1) ]
              txn.success = [ txn.put('txn-test', 'success') ]
              txn.failure = [ txn.put('txn-test', 'failed') ]
            end
          end
          it 'sets correct key' do
            expect(conn.get('txn-test').kvs.first.value).to eq('failed')
          end
        end
      end

      describe 'txn.mod_revision' do
        before { conn.put('txn', 'value') }
        after { conn.del('txn') }
        context 'success' do
          subject! do
            conn.transaction do |txn|
              txn.compare = [ txn.mod_revision('txn', :less, 1000) ]
              txn.success = [ txn.put('txn-test', 'success') ]
              txn.failure = [ txn.put('txn-test', 'failed') ]
            end
          end
          it 'sets correct key' do
            expect(conn.get('txn-test').kvs.first.value).to eq('success')
          end
        end
        context 'failure' do
          subject! do
            conn.transaction do |txn|
              txn.compare = [ txn.mod_revision('txn', :greater, 1000) ]
              txn.success = [ txn.put('txn-test', 'success') ]
              txn.failure = [ txn.put('txn-test', 'failed') ]
            end
          end
          it 'sets correct key' do
            expect(conn.get('txn-test').kvs.first.value).to eq('failed')
          end
        end
      end

      describe 'txn.version' do
        before { conn.put('txn', 'value') }
        after { conn.del('txn') }
        context 'success' do
          subject! do
            conn.transaction do |txn|
              txn.compare = [ txn.version('txn', :equal, 1) ]
              txn.success = [ txn.put('txn-test', 'success') ]
              txn.failure = [ txn.put('txn-test', 'failed') ]
            end
          end
          it 'sets correct key' do
            expect(conn.get('txn-test').kvs.first.value).to eq('success')
          end
        end
        context 'failure' do
          subject! do
            conn.transaction do |txn|
              txn.compare = [ txn.version('txn', :equal, 100)]
              txn.success = [ txn.put('txn-test', 'success') ]
              txn.failure = [ txn.put('txn-test', 'failed') ]
            end
          end
          it 'sets correct key' do
            expect(conn.get('txn-test').kvs.first.value).to eq('failed')
          end
        end
      end
    end

    describe "namespace" do 

      describe '#get' do
        let(:get_conn) { local_connection_with_namespace("/namespace-get/") }

        before do
          conn.put('/apples/', 'app')
          conn.put('/namespace-get/apple', 'apple')
          conn.put('/namespace-get/apples', 'apples')
          conn.put('/namespace-get/appless', 'appless')
        end

        it 'returns key w/o namespace' do 
          expect(get_conn.get("apple").kvs.last.value).to eq('apple')
        end

        it 'returns keys w/o namespace' do 
          expect(get_conn.get("apple", range_end: 'applf').kvs.size).to eq(3)
        end

        it 'returns all keys under namespace' do 
          expect(get_conn.get("", range_end: "\0").kvs.size).to eq(3)
        end
      end

      describe '#put' do
        let(:put_conn) { local_connection_with_namespace("/namespace-put/") }

        before do
          put_conn.put('apple_put', 'test')
        end
        it 'returns key with namespace' do 
          expect(conn.get("/namespace-put/apple_put").kvs.last.value).to eq('test')
        end
      end

      describe '#del' do 
        let(:del_conn) { local_connection_with_namespace("/del-test/") }
        
        context 'zero-byte' do 
          before do 
            del_conn.put('test', "key")
            del_conn.put('test2', "key2")
            conn.put('wall', 'zzzz')
            conn.put('walzz', 'adsfas')
          end

          it 'deleting all keys should be scoped to namespace' do 
            resp = del_conn.del("", range_end: "\0")
            expect(resp.deleted).to eq(2)
            expect(conn.get("wall").kvs.last.value).to eq('zzzz')
          end
        end

        context 'no range' do
          before { del_conn.put('test', 'value') }
          it 'deleting key should be scoped to namespace' do
            resp = del_conn.del('test')
            expect(resp.deleted).to eq(1)
            expect(del_conn.get('test').kvs).to be_empty
          end
        end

        context 'ranged del' do
          before do
            del_conn.put('test', 'value')
            del_conn.put('testt', 'value')
          end
          it 'deleting keys should be scoped to namespace' do
            resp = del_conn.del('test', range_end: 'testtt')
            expect(resp.deleted).to eq(2)
            expect(del_conn.get('test', range_end: 'testtt').kvs).to be_empty
          end
        end
      end

      describe '#transaction' do
        let(:trans_conn) { local_connection_with_namespace("/namespace/") }

        describe 'txn.value' do
          before { trans_conn.put('txn', 'value') }
          after { trans_conn.del('txn') }
          context 'success' do
            subject! do
              trans_conn.transaction do |txn|
                txn.compare = [ txn.value('txn', :equal, 'value') ]
                txn.success = [ txn.put('txn-test', 'success') ]
                txn.failure = [ txn.put('txn-test', 'failed') ]
              end
            end
            it 'sets correct key' do
              expect(trans_conn.get('txn-test').kvs.first.value).to eq('success')
              expect(conn.get("/namespace/txn-test").kvs.first.value).to eq('success')
            end
            it "raises a GRPC::DeadlineExceeded exception when it takes too long"  do
              expect do
                trans_conn.transaction(timeout: 0) do |txn|
                  txn.compare = [ txn.value('txn', :equal, 'value') ]
                  txn.success = [ txn.put('txn-test', 'success') ]
                  txn.failure = [ txn.put('txn-test', 'failed') ]
                end
              end.to raise_exception(GRPC::DeadlineExceeded)
            end
            it "accepts a timeout" do
              expect do
                trans_conn.transaction(timeout: 1) do |txn|
                  txn.compare = [ txn.value('txn', :equal, 'value') ]
                  txn.success = [ txn.put('txn-test', 'success') ]
                  txn.failure = [ txn.put('txn-test', 'failed') ]
                end
              end.to_not raise_exception
            end
          end
          context "success, value with lease" do
            let!(:lease_id) { trans_conn.lease_grant(2)['ID'] }
            subject! do
              trans_conn.transaction do |txn|
                txn.compare = [ txn.value('txn', :equal, 'value') ]
                txn.success = [ txn.put('txn-test', 'success', lease_id) ]
                txn.failure = [ txn.put('txn-test', 'failed', lease_id) ]
              end
            end
            it 'sets correct key, with a lease' do
              expect(trans_conn.get('txn-test').kvs.first.value).to eq('success')
              expect(trans_conn.get('txn-test').kvs.first.lease).to eq(lease_id)
            end
          end
          context 'failure' do
            subject! do
              trans_conn.transaction do |txn|
                txn.compare = [ txn.value('txn', :equal, 'notright') ]
                txn.success = [ txn.put('txn-test', 'success') ]
                txn.failure = [ txn.put('txn-test', 'failed') ]
              end
            end
            it 'sets correct key' do
              expect(trans_conn.get('txn-test').kvs.first.value).to eq('failed')
            end
          end
        end
  
        describe 'txn.create_revision' do
          before { trans_conn.put('txn', 'value') }
          after { trans_conn.del('txn') }
          context 'success' do
            subject! do
              trans_conn.transaction do |txn|
                txn.compare = [ txn.create_revision('txn', :greater, 1) ]
                txn.success = [ txn.put('txn-test', 'success') ]
                txn.failure = [ txn.put('txn-test', 'failed') ]
              end
            end
            it 'sets correct key' do
              expect(trans_conn.get('txn-test').kvs.first.value).to eq('success')
            end
          end
          context 'failure' do
            subject! do
              trans_conn.transaction do |txn|
                txn.compare = [ txn.create_revision('txn', :equal, 1) ]
                txn.success = [ txn.put('txn-test', 'success') ]
                txn.failure = [ txn.put('txn-test', 'failed') ]
              end
            end
            it 'sets correct key' do
              expect(trans_conn.get('txn-test').kvs.first.value).to eq('failed')
              expect(conn.get('/namespace/txn-test').kvs.first.value).to eq('failed')
            end
          end
        end
  
        describe 'txn.mod_revision' do
          before { trans_conn.put('txn', 'value') }
          after { trans_conn.del('txn') }
          context 'success' do
            subject! do
              trans_conn.transaction do |txn|
                txn.compare = [ txn.mod_revision('txn', :less, 1000) ]
                txn.success = [ txn.put('txn-test', 'success') ]
                txn.failure = [ txn.put('txn-test', 'failed') ]
              end
            end
            it 'sets correct key' do
              expect(trans_conn.get('txn-test').kvs.first.value).to eq('success')
              expect(conn.get('/namespace/txn-test').kvs.first.value).to eq('success')
            end
          end
          context 'failure' do
            subject! do
              trans_conn.transaction do |txn|
                txn.compare = [ txn.mod_revision('txn', :greater, 1000) ]
                txn.success = [ txn.put('txn-test', 'success') ]
                txn.failure = [ txn.put('txn-test', 'failed') ]
              end
            end
            it 'sets correct key' do
              expect(trans_conn.get('txn-test').kvs.first.value).to eq('failed')
              expect(conn.get('/namespace/txn-test').kvs.first.value).to eq('failed')

            end
          end
        end
  
        describe 'txn.version' do
          before { trans_conn.put('txn-version', 'value') }
          after { trans_conn.del('txn-version') }
          context 'success' do
            subject! do
              trans_conn.transaction do |txn|
                txn.compare = [ txn.version('txn-version', :equal, 1) ]
                txn.success = [ txn.put('txn-test', 'success') ]
                txn.failure = [ txn.put('txn-test', 'failed') ]
              end
            end
            it 'sets correct key' do
              expect(trans_conn.get('txn-test').kvs.first.value).to eq('success')
              expect(conn.get('/namespace/txn-test').kvs.first.value).to eq('success')
            end
          end
          context 'failure' do
            subject! do
              trans_conn.transaction do |txn|
                txn.compare = [ txn.version('txn', :equal, 100)]
                txn.success = [ txn.put('txn-test', 'success') ]
                txn.failure = [ txn.put('txn-test', 'failed') ]
              end
            end
            it 'sets correct key' do
              expect(trans_conn.get('txn-test').kvs.first.value).to eq('failed')
              expect(conn.get('/namespace/txn-test').kvs.first.value).to eq('failed')
            end
          end
        end
      end

      # Locking is not implemented in etcd v3.1.X
      unless $instance.version < Gem::Version.new("3.2.0")
        describe "locking" do 
          let(:ns_conn) { local_connection_with_namespace("/namespace/") }

          describe '#lock' do
            let(:lease_id) { lease_stub.lease_grant(10)['ID'] }
            subject { ns_conn.lock('mylocklock', lease_id) }
            it 'should lock key under specified namespace' do 
              expect(conn.get("/namespace/#{subject.key}").kvs).to_not be_empty
            end
          end

          describe '#with_lock' do
            let(:lease_id) { lease_stub.lease_grant(10)['ID'] }
            let(:lease_id_2) { lease_stub.lease_grant(15)['ID'] }
            it 'enforces lock' do
              ns_conn.with_lock('mylock', lease_id) do
                expect { ns_conn.lock('mylock', lease_id_2, timeout: 0.1) }
                  .to raise_error(GRPC::DeadlineExceeded)
              end
            end
          end
        end
      end
    end
  end
end
